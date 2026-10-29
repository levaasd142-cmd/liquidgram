import os
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "Migration")

/// Moves the website data of version 1 into the app's origin. Version 1 served the web app at `http://127.0.0.1:47821`,
/// so the Telegram session, the accounts and the API keys in its `localStorage`, and the cached chats, the Liquidgram
/// settings, the kept deleted messages and the passcode vault in its IndexedDB belong to that origin; at
/// `liquidgram-web://app` the web app would start signed out.
///
/// Once per install, before the page first loads, a hidden web view opens an empty document of each origin with
/// `loadHTMLString(_:baseURL:)`, which gives a document the origin of its base URL without any request, so no server
/// and no port are involved. `Resources/legacy-data.js` reads every `localStorage` item and IndexedDB record of the old
/// origin and writes them into the new one, unless the new origin has a session already. Then the old data is
/// removed. Caches, which the web app fills again, are not moved.
///
/// A record that cannot be copied, such as one holding a `CryptoKey`, is left out and logged.
///
/// The launch waits for the migration at most 2 seconds. When it takes longer, the web app starts meanwhile and
/// reloads once the data has arrived. A failed migration keeps the old data and runs again at the next launch, at most
/// three times. Everything runs on the main queue.
final class LegacyDataMigration: NSObject {
  static let legacyOriginURL = URL(string: "http://127.0.0.1:47821/")!

  /// `WKWebsiteDataRecord` names the old origin's data by its host
  private static let legacyRecordName = "127.0.0.1"
  private static let doneKey = "LiquidgramLegacyDataMigrated"
  private static let attemptsKey = "LiquidgramLegacyDataMigrationAttempts"
  private static let maxAttempts = 3
  private static let launchWaitTime: TimeInterval = 2
  private static let stepTimeout: TimeInterval = 20
  private static let scriptName = "legacy-data"
  private static let scriptExtension = "js"
  private static let blankPage = "<!doctype html><meta charset=\"utf-8\"><title>Liquidgram</title>"

  /// The migration in progress, kept until it ends
  private static var current: LegacyDataMigration?

  private let dataStore = WKWebsiteDataStore.default()
  /// Starts the web app; `nil` once it was called
  private var startApp: (() -> Void)?
  private let reloadApp: () -> Void
  private var isRunning = true
  private var webView: WKWebView?
  private var navigationCompletion: ((Error?) -> Void)?
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
      return
    }
    let migration = LegacyDataMigration(startApp: startApp, reloadApp: reloadApp)
    current = migration
    migration.start()
  }

  private func start() {
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchWaitTime) { [weak self] in
      self?.startAppWhileRunning()
    }
    dataStore.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { [weak self] records in
      guard let self, self.isRunning else {
        return
      }
      guard let legacyRecord = records.first(where: { $0.displayName == Self.legacyRecordName }) else {
        self.finish(.nothingToMove)
        return
      }
      self.move(legacyRecord)
    }
  }

  private func move(_ legacyRecord: WKWebsiteDataRecord) {
    guard let script = Self.loadScript() else {
      finish(.failed("legacy-data.js is missing from the app bundle"))
      return
    }
    webView = makeWebView()
    open(Self.legacyOriginURL) { [weak self] in
      self?.run(script + "\nreturn await exportLegacyData();", arguments: [:]) { exported in
        guard let self, let payload = exported["payload"] as? String else {
          self?.finish(.failed("the old origin gave no data"))
          return
        }
        let exportedRecords = (exported["recordCount"] as? NSNumber)?.intValue ?? 0
        let skipped = exported["skipped"] as? [String] ?? []
        for record in skipped {
          logger.error("Could not move a record of version 1: \(record, privacy: .public)")
        }
        self.open(AppSchemeHandler.appURL) { [weak self] in
          self?.run(script + "\nreturn await importLegacyData(payload);", arguments: ["payload": payload]) { imported in
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
            guard importedRecords == exportedRecords else {
              self.finish(.failed("wrote \(importedRecords) of \(exportedRecords) records"))
              return
            }
            let summary = "\(items) localStorage items, \(importedRecords) IndexedDB records, \(skipped.count) left out, "
              + "\(payload.utf8.count) bytes"
            self.removeLegacyData(legacyRecord, outcome: .moved(summary))
          }
        }
      }
    }
  }

  private func makeWebView() -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    // With its handler, the app's scheme has a regular origin, like the app's page
    configuration.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: AppSchemeHandler.scheme)
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    return webView
  }

  /// Opens an empty document of the origin of `baseURL`
  private func open(_ baseURL: URL, then next: @escaping () -> Void) {
    startStepTimeout()
    navigationCompletion = { [weak self] error in
      guard let error else {
        next()
        return
      }
      self?.finish(.failed("could not open \(baseURL.absoluteString): \(error.localizedDescription)"))
    }
    webView?.loadHTMLString(Self.blankPage, baseURL: baseURL)
  }

  private func run(_ body: String, arguments: [String: Any], then next: @escaping ([String: Any]) -> Void) {
    startStepTimeout()
    webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { [weak self] result in
      guard let self, self.isRunning else {
        return
      }
      self.stepTimeoutItem?.cancel()
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

  private func startStepTimeout() {
    stepTimeoutItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      self?.finish(.failed("a step took longer than \(Int(Self.stepTimeout)) seconds"))
    }
    stepTimeoutItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.stepTimeout, execute: item)
  }

  private func removeLegacyData(_ legacyRecord: WKWebsiteDataRecord, outcome: Outcome) {
    startStepTimeout()
    dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: [legacyRecord]) { [weak self] in
      self?.finish(outcome)
    }
  }

  /// The launch goes on while a slow migration runs
  private func startAppWhileRunning() {
    guard isRunning, let startApp else {
      return
    }
    self.startApp = nil
    logger.notice("The data of version 1 is still moving; the web app starts meanwhile")
    startApp()
  }

  private func finish(_ outcome: Outcome) {
    guard isRunning else {
      return
    }
    isRunning = false
    stepTimeoutItem?.cancel()
    webView?.navigationDelegate = nil
    webView?.stopLoading()
    webView = nil
    navigationCompletion = nil

    let defaults = UserDefaults.standard
    switch outcome {
    case .nothingToMove:
      defaults.set(true, forKey: Self.doneKey)
      logger.info("No data of version 1 to move")
    case .appHasSession:
      defaults.set(true, forKey: Self.doneKey)
      logger.notice("The app's origin has a session; the data of version 1 stays where it is")
    case .moved(let summary):
      defaults.set(true, forKey: Self.doneKey)
      logger.notice("Moved the data of version 1 to the app's origin: \(summary, privacy: .public)")
    case .failed(let reason):
      let attempts = defaults.integer(forKey: Self.attemptsKey) + 1
      defaults.set(attempts, forKey: Self.attemptsKey)
      if attempts >= Self.maxAttempts {
        defaults.set(true, forKey: Self.doneKey)
      }
      logger.error("Could not move the data of version 1, attempt \(attempts): \(reason, privacy: .public)")
    }
    TestHooks.recordMigration(outcome.description)

    if let startApp {
      self.startApp = nil
      startApp()
    } else if case .moved = outcome {
      reloadApp()
    }
    Self.current = nil
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
    completeNavigation(nil)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    completeNavigation(error)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    completeNavigation(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish(.failed("the web content process ended"))
  }

  private func completeNavigation(_ error: Error?) {
    guard let navigationCompletion else {
      return
    }
    self.navigationCompletion = nil
    stepTimeoutItem?.cancel()
    navigationCompletion(error)
  }
}

private enum Outcome: CustomStringConvertible {
  case nothingToMove
  case appHasSession
  case moved(String)
  case failed(String)

  var description: String {
    switch self {
    case .nothingToMove:
      return "nothing to move"
    case .appHasSession:
      return "the app's origin has a session; kept the old data"
    case .moved(let summary):
      return "moved \(summary); removed the old data"
    case .failed(let reason):
      return "failed: \(reason)"
    }
  }
}
