import os
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "Migration")

/// Moves the website data of version 1 into the app's origin. Version 1 served the web app at `http://127.0.0.1:47821`,
/// so the Telegram session, the accounts and the API keys in its `localStorage`, and the cached chats, the Liquidgram
/// settings, the kept deleted messages and the passcode vault in its IndexedDB belong to that origin; at
/// `liquidgram-web://app` the web app would start signed out.
///
/// Once per install, before the page first loads, two hidden web views open an empty document of each origin with
/// `loadHTMLString(_:baseURL:)`, which gives a document the origin of its base URL without any request, so no server
/// and no port are involved. Both load at once, so their web processes start together. `Resources/legacy-data.js`
/// reads every `localStorage` item and IndexedDB record of the old origin and writes them into the new one, unless the
/// new origin has a session already. Caches, which the web app fills again, are not moved.
///
/// A record that cannot be copied, such as one holding a `CryptoKey`, is left out and logged.
///
/// The launch waits for the migration at most 2 seconds. When it takes longer, the web app starts meanwhile and
/// reloads once the data has arrived. A failed migration keeps the old data and runs again at the next launch, at most
/// three times. Once the data is in the app's origin, the old origin's data is removed in the background; a launch
/// that ends first leaves the removal to the next one. Everything runs on the main queue.
final class LegacyDataMigration: NSObject {
  static let legacyOriginURL = URL(string: "http://127.0.0.1:47821/")!

  /// `WKWebsiteDataRecord` names the old origin's data by its host
  private static let legacyRecordName = "127.0.0.1"
  private static let doneKey = "LiquidgramLegacyDataMigrated"
  private static let attemptsKey = "LiquidgramLegacyDataMigrationAttempts"
  /// Set while the old origin's data, which has moved, may still be on disk
  private static let removalPendingKey = "LiquidgramLegacyDataRemovalPending"
  private static let maxAttempts = 3
  private static let launchWaitTime: TimeInterval = 2
  private static let stepTimeout: TimeInterval = 20
  private static let scriptName = "legacy-data"
  private static let scriptExtension = "js"
  private static let blankPage = "<!doctype html><meta charset=\"utf-8\"><title>Liquidgram</title>"

  /// The migration in progress, kept until it ends
  private static var current: LegacyDataMigration?

  /// Whether the data of version 1 is moving at the moment
  static var isMoving: Bool {
    current?.isRunning == true
  }

  private let dataStore = WKWebsiteDataStore.default()
  private let startTime = Date()
  /// Starts the web app; `nil` once it was called
  private var startApp: (() -> Void)?
  private let reloadApp: () -> Void
  private var isRunning = true
  private var script = ""
  /// The empty document of the old origin, until its data is read
  private var exportView: WKWebView?
  /// The empty document of the app's origin
  private var importView: WKWebView?
  private var isImportViewReady = false
  /// The old origin's data, until the import takes it
  private var exported: Export?
  private var stepTimeoutItem: DispatchWorkItem?

  private init(startApp: @escaping () -> Void, reloadApp: @escaping () -> Void) {
    self.startApp = startApp
    self.reloadApp = reloadApp
    super.init()
  }

  /// Calls `startApp` once the data of version 1 is in the app's origin, or after 2 seconds at most, on the main
  /// queue. `reloadApp` follows if the data arrives after the app started.
  static func runIfNeeded(startApp: @escaping () -> Void, reloadApp: @escaping () -> Void) {
    guard !UserDefaults.standard.bool(forKey: doneKey), current == nil else {
      startApp()
      removeLegacyDataIfPending()
      return
    }
    let migration = LegacyDataMigration(startApp: startApp, reloadApp: reloadApp)
    current = migration
    migration.start()
  }

  /// Removes the old origin's data in the background once it has moved
  private static func removeLegacyDataIfPending() {
    guard current == nil, UserDefaults.standard.bool(forKey: removalPendingKey) else {
      return
    }
    let dataStore = WKWebsiteDataStore.default()
    let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
    let startTime = Date()
    dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
      let legacyRecords = records.filter { $0.displayName == legacyRecordName }
      dataStore.removeData(ofTypes: dataTypes, for: legacyRecords) {
        UserDefaults.standard.removeObject(forKey: removalPendingKey)
        logger.notice("Removed the data of version 1 in \(milliseconds(since: startTime)) ms")
      }
    }
  }

  private static func milliseconds(since date: Date) -> Int {
    Int(Date().timeIntervalSince(date) * 1000)
  }

  private func start() {
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchWaitTime) { [weak self] in
      self?.startAppWhileRunning()
    }
    startStepTimeout()
    dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { [weak self] records in
      guard let self, self.isRunning else {
        return
      }
      guard records.contains(where: { $0.displayName == Self.legacyRecordName }) else {
        self.finish(.nothingToMove)
        return
      }
      self.move()
    }
  }

  private func move() {
    guard let script = Self.loadScript() else {
      finish(.failed("legacy-data.js is missing from the app bundle"))
      return
    }
    self.script = script
    startStepTimeout()
    exportView = makeWebView(loading: Self.legacyOriginURL)
    importView = makeWebView(loading: AppSchemeHandler.appURL)
  }

  private func makeWebView(loading baseURL: URL) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    // With its handler, the app's scheme has a regular origin, like the app's page
    configuration.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: AppSchemeHandler.scheme)
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.loadHTMLString(Self.blankPage, baseURL: baseURL)
    return webView
  }

  private func runExport() {
    run(script + "\nreturn await exportLegacyData();", arguments: [:], in: exportView) { [weak self] result in
      guard let self else {
        return
      }
      guard let payload = result["payload"] as? String else {
        self.finish(.failed("the old origin gave no data"))
        return
      }
      let skipped = result["skipped"] as? [String] ?? []
      for record in skipped {
        logger.error("Could not move a record of version 1: \(record, privacy: .public)")
      }
      self.exported = Export(
        payload: payload,
        recordCount: (result["recordCount"] as? NSNumber)?.intValue ?? 0,
        skippedCount: skipped.count
      )
      self.close(self.exportView)
      self.exportView = nil
      logger.info("Read the data of version 1 after \(Self.milliseconds(since: self.startTime)) ms")
      self.runImportIfReady()
    }
  }

  /// Writes the old origin's data once it was read and the app's origin has its document
  private func runImportIfReady() {
    guard isImportViewReady, let exported else {
      return
    }
    self.exported = nil
    let body = script + "\nreturn await importLegacyData(payload);"
    run(body, arguments: ["payload": exported.payload], in: importView) { [weak self] imported in
      guard let self else {
        return
      }
      // The user signed in again after an earlier attempt failed; the old data stays as it is
      if NativeRequestHandler.readBool(imported["hasSession"]) == true {
        self.finish(.appHasSession)
        return
      }
      let importedRecords = (imported["recordCount"] as? NSNumber)?.intValue ?? -1
      let items = (imported["localStorageCount"] as? NSNumber)?.intValue ?? 0
      guard importedRecords == exported.recordCount else {
        self.finish(.failed("wrote \(importedRecords) of \(exported.recordCount) records"))
        return
      }
      self.finish(.moved(
        "\(items) localStorage items, \(importedRecords) IndexedDB records, \(exported.skippedCount) left out, "
          + "\(exported.payload.utf8.count) bytes"
      ))
    }
  }

  private func run(
    _ body: String,
    arguments: [String: Any],
    in webView: WKWebView?,
    then next: @escaping ([String: Any]) -> Void
  ) {
    startStepTimeout()
    webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { [weak self] result in
      guard let self, self.isRunning else {
        return
      }
      switch result {
      case .success(let value):
        guard let object = value as? [String: Any] else {
          self.finish(.failed("unexpected result \(String(describing: value))"))
          return
        }
        next(object)
      case .failure(let error):
        self.finish(.failed(error.localizedDescription))
      }
    }
  }

  /// Every step restarts the timeout, which covers the documents that still load as well
  private func startStepTimeout() {
    stepTimeoutItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.finish(.failed("a step took longer than \(Int(Self.stepTimeout)) seconds"))
    }
    stepTimeoutItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepTimeout, execute: item)
  }

  private func close(_ webView: WKWebView?) {
    webView?.navigationDelegate = nil
    webView?.stopLoading()
  }

  /// The launch goes on while a slow migration runs
  private func startAppWhileRunning() {
    guard isRunning, let startApp else {
      return
    }
    self.startApp = nil
    let waitTime = Int(Self.launchWaitTime)
    logger.notice("The data of version 1 is still moving after \(waitTime) s; the web app starts meanwhile")
    startApp()
  }

  private func finish(_ outcome: Outcome) {
    guard isRunning else {
      return
    }
    isRunning = false
    stepTimeoutItem?.cancel()
    close(exportView)
    close(importView)
    exportView = nil
    importView = nil
    exported = nil

    let defaults = UserDefaults.standard
    let duration = Self.milliseconds(since: startTime)
    switch outcome {
    case .nothingToMove:
      defaults.set(true, forKey: Self.doneKey)
      logger.info("No data of version 1 to move")
    case .appHasSession:
      defaults.set(true, forKey: Self.doneKey)
      logger.notice("The app's origin has a session; the data of version 1 stays where it is")
    case .moved(let summary):
      defaults.set(true, forKey: Self.doneKey)
      defaults.set(true, forKey: Self.removalPendingKey)
      logger.notice("Moved the data of version 1 to the app's origin in \(duration) ms: \(summary, privacy: .public)")
    case .failed(let reason):
      let attempts = defaults.integer(forKey: Self.attemptsKey) + 1
      defaults.set(attempts, forKey: Self.attemptsKey)
      if attempts >= Self.maxAttempts {
        defaults.set(true, forKey: Self.doneKey)
      }
      logger.error(
        "Could not move the data of version 1, attempt \(attempts), after \(duration) ms: \(reason, privacy: .public)"
      )
    }

    let willReloadApp = startApp == nil && outcome.hasMovedData
    TestHooks.recordMigration(outcome.description, willReloadApp: willReloadApp)
    if let startApp {
      self.startApp = nil
      startApp()
    } else if willReloadApp {
      reloadApp()
    }
    Self.current = nil
    Self.removeLegacyDataIfPending()
  }

  private static func loadScript() -> String? {
    guard let url = Bundle.main.url(forResource: scriptName, withExtension: scriptExtension) else {
      return nil
    }
    return try? String(contentsOf: url, encoding: .utf8)
  }
}

extension LegacyDataMigration: WKNavigationDelegate {
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard isRunning else {
      return
    }
    if webView === exportView {
      runExport()
    } else if webView === importView {
      isImportViewReady = true
      runImportIfReady()
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    failToOpen(webView, error)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    failToOpen(webView, error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish(.failed("the web content process ended"))
  }

  private func failToOpen(_ webView: WKWebView, _ error: Error) {
    let url = webView === exportView ? Self.legacyOriginURL : AppSchemeHandler.appURL
    finish(.failed("could not open \(url.absoluteString): \(error.localizedDescription)"))
  }
}

/// What the old origin gave
private struct Export {
  /// `localStorage` and IndexedDB as JSON, for `importLegacyData`
  let payload: String
  let recordCount: Int
  let skippedCount: Int
}

private enum Outcome: CustomStringConvertible {
  case nothingToMove
  case appHasSession
  case moved(String)
  case failed(String)

  var hasMovedData: Bool {
    if case .moved = self {
      return true
    }
    return false
  }

  var description: String {
    switch self {
    case .nothingToMove:
      return "nothing to move"
    case .appHasSession:
      return "the app's origin has a session; kept the old data"
    case .moved(let summary):
      return "moved \(summary)"
    case .failed(let reason):
      return "failed: \(reason)"
    }
  }
}
