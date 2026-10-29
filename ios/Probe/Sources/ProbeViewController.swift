import os
import UIKit
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "Probe")

private enum ProbePhase: String {
  case main
  case verify
}

private struct ProbeOrigin {
  let label: String
  let baseURL: URL
}

/// Resumes a continuation once, with whichever comes first: the awaited event or the timeout. Used on the main queue.
private final class OnceWaiter {
  private var continuation: CheckedContinuation<Bool, Never>?

  init(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = continuation
  }

  func resume(_ value: Bool) {
    continuation?.resume(returning: value)
    continuation = nil
  }
}

/// Loads the probe pages and the real web app over the custom scheme and over the loopback server, records every
/// result in `Documents/probe-<phase>/report.json` and snapshots each page. The runner launches the app twice:
/// `-ProbePhase main` stores markers in website storage and `-ProbePhase verify` reads them after the relaunch.
/// The web view is configured like the app's, with the same environment line and `bridge.js`.
final class ProbeViewController: UIViewController {
  private static let phaseKey = "ProbePhase"
  private static let runIdKey = "ProbeRunId"
  private static let probeHandlerName = "probe"
  private static let bridgeHandlerName = "liquidgram"
  private static let applicationName = "Liquidgram"
  private static let customOriginLabel = "custom"
  private static let httpOriginLabel = "http"
  private static let featuresPath = "__probe/features.html"
  private static let embedPath = "__probe/embed.html"
  private static let referrerProbeHost = "probe-referrer.invalid"
  private static let environmentScript =
    "window.__liquidgramNative = { platform: 'ios', version: 'probe', notificationPermission: 'default' };"
  private static let apiKeysFormQuery = "return Boolean(document.querySelector('#auth-api-credentials-form'))"
  private static let realAppChecksBody = """
    const checks = await import('/__probe/realapp-checks.js');
    return JSON.stringify(await checks.runChecks());
    """
  private static let featuresTimeout: TimeInterval = 300
  private static let verifyTimeout: TimeInterval = 120
  private static let embedTimeout: TimeInterval = 40
  private static let realAppTimeout: TimeInterval = 90
  private static let serverTimeout: TimeInterval = 30
  private static let realAppSettleNanoseconds: UInt64 = 5_000_000_000
  private static let flushNanoseconds: UInt64 = 3_000_000_000
  private static let pollNanoseconds: UInt64 = 500_000_000
  // `WebKitErrorFrameLoadInterruptedByPolicyChange`, reported when a navigation becomes a download
  private static let webKitErrorDomain = "WebKitErrorDomain"
  private static let frameLoadInterruptedCode = 102
  private static let reportFileName = "report.json"
  private static let doneFileName = "done.json"

  private let phase: ProbePhase
  private let runId: String
  private let outputDirectory: URL
  private let startDate: Date
  private let server = LocalServer()
  private let schemeHandler: RecordingSchemeHandler
  private let webView: WKWebView
  private var scenarios: [ScenarioRecord] = []
  private var currentScenario: ScenarioRecord?
  private var pageWaiter: OnceWaiter?
  private var downloadDestinations: [WKDownload: URL] = [:]
  private var userAgent = ""

  init() {
    let defaults = UserDefaults.standard
    let phase = ProbePhase(rawValue: defaults.string(forKey: Self.phaseKey) ?? "") ?? .main
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let startDate = Date()
    let schemeHandler = RecordingSchemeHandler(base: AppSchemeHandler(), startDate: startDate)
    let messageHandler = WeakMessageHandler()
    self.phase = phase
    runId = defaults.string(forKey: Self.runIdKey) ?? "local"
    outputDirectory = documents.appendingPathComponent("probe-\(phase.rawValue)", isDirectory: true)
    self.startDate = startDate
    self.schemeHandler = schemeHandler
    webView = Self.makeWebView(schemeHandler: schemeHandler, messageHandler: messageHandler)
    super.init(nibName: nil, bundle: nil)
    messageHandler.target = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func loadView() {
    view = webView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    webView.navigationDelegate = self
    webView.uiDelegate = self
    Task {
      await runProbe()
    }
  }

  private static func makeWebView(
    schemeHandler: RecordingSchemeHandler,
    messageHandler: WeakMessageHandler
  ) -> WKWebView {
    let userContentController = WKUserContentController()
    userContentController.add(messageHandler, name: probeHandlerName)
    userContentController.add(messageHandler, name: bridgeHandlerName)
    for source in makeUserScriptSources() {
      userContentController.addUserScript(
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
      )
    }

    let configuration = WKWebViewConfiguration()
    configuration.userContentController = userContentController
    configuration.websiteDataStore = .default()
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.applicationNameForUserAgent = applicationName
    configuration.setURLSchemeHandler(schemeHandler, forURLScheme: AppSchemeHandler.scheme)

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.isOpaque = false
    webView.backgroundColor = .white
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    if #available(iOS 16.4, *) {
      webView.isInspectable = true
    }
    return webView
  }

  /// The probe's reporter first, then the app's own document-start scripts
  private static func makeUserScriptSources() -> [String] {
    var sources: [String] = []
    if let reporter = loadScript(named: "probe-inject") {
      sources.append(reporter)
    }
    sources.append(environmentScript)
    if let bridge = loadScript(named: "bridge") {
      sources.append(bridge)
    }
    return sources
  }

  private static func loadScript(named name: String) -> String? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
          let source = try? String(contentsOf: url, encoding: .utf8) else {
      logger.error("\(name, privacy: .public).js is missing from the bundle")
      return nil
    }
    return source
  }

  /// Encodes `value` as a JavaScript string literal
  private static func makeJavaScriptString(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
          let arrayLiteral = String(data: data, encoding: .utf8) else {
      return "''"
    }
    return String(arrayLiteral.dropFirst().dropLast())
  }

  private static func describe(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else {
      return String(describing: value)
    }
    return text
  }

  private var elapsed: Double {
    Date().timeIntervalSince(startDate)
  }

  private func runProbe() async {
    prepareOutputDirectory()
    logger.notice("Probe \(self.phase.rawValue, privacy: .public) of run \(self.runId, privacy: .public) started")
    let isServerReady = await waitForServer()
    let origins = [
      ProbeOrigin(label: Self.customOriginLabel, baseURL: AppSchemeHandler.appURL),
      ProbeOrigin(label: Self.httpOriginLabel, baseURL: LocalServer.appURL),
    ]
    for origin in origins {
      guard origin.label == Self.customOriginLabel || isServerReady else {
        let scenario = beginScenario("server", origin: origin, url: origin.baseURL)
        scenario.status = "skipped"
        scenario.checks.append(ProbeCheck(name: "server-ready", ok: false, detail: "LocalServer did not become ready"))
        currentScenario = nil
        continue
      }

      switch phase {
      case .main:
        await runPage("features", path: Self.featuresPath, origin: origin, timeout: Self.featuresTimeout)
        await runRealApp(origin: origin)
        await runPage("embed", path: Self.embedPath, origin: origin, timeout: Self.embedTimeout)
      case .verify:
        await runPage("verify", path: Self.featuresPath, origin: origin, timeout: Self.verifyTimeout)
      }
    }

    if case .success(let value) = await callPage("return navigator.userAgent") {
      userAgent = value as? String ?? ""
    }
    let dataRecords = await fetchDataRecords()
    // Website storage reaches the disk asynchronously, and the runner terminates the app once the marker exists
    try? await Task.sleep(nanoseconds: Self.flushNanoseconds)
    writeReport(dataRecords: dataRecords)
    writeDoneMarker()
    logger.notice("Probe \(self.phase.rawValue, privacy: .public) finished")
  }

  private func waitForServer() async -> Bool {
    await withCheckedContinuation { continuation in
      let waiter = OnceWaiter(continuation)
      server.whenReady {
        waiter.resume(true)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.serverTimeout) {
        waiter.resume(false)
      }
    }
  }

  /// Loads a probe page, which reports its checks and ends with a `done` message
  private func runPage(_ name: String, path: String, origin: ProbeOrigin, timeout: TimeInterval) async {
    var components = URLComponents(url: origin.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
    components?.queryItems = [
      URLQueryItem(name: "phase", value: phase.rawValue),
      URLQueryItem(name: "origin", value: origin.label),
      URLQueryItem(name: "run", value: runId),
    ]
    guard let url = components?.url else {
      logger.error("Could not build the URL of \(path, privacy: .public)")
      return
    }

    let scenario = beginScenario(name, origin: origin, url: url)
    webView.load(URLRequest(url: url))
    let isDone = await waitForPageDone(timeout: timeout)
    scenario.status = isDone ? "done" : "timeout"
    await endScenario(scenario)
  }

  /// Loads the real web app, waits for the API keys screen and runs `realapp-checks.js` inside it
  private func runRealApp(origin: ProbeOrigin) async {
    let scenario = beginScenario("realapp", origin: origin, url: origin.baseURL)
    webView.load(URLRequest(url: origin.baseURL))
    let deadline = Date().addingTimeInterval(Self.realAppTimeout)
    var hasApiKeysForm = false
    while !hasApiKeysForm && Date() < deadline {
      try? await Task.sleep(nanoseconds: Self.pollNanoseconds)
      hasApiKeysForm = await evaluateBoolean(Self.apiKeysFormQuery)
    }
    recordEvent("api-keys-form", hasApiKeysForm ? "rendered after \(elapsed - scenario.startedAt) s" : "missing")

    // Errors and workers that come after the first render
    try? await Task.sleep(nanoseconds: Self.realAppSettleNanoseconds)
    await runRealAppChecks(in: scenario)
    recordRealAppErrors(in: scenario)
    scenario.status = "done"
    await endScenario(scenario)
  }

  private func runRealAppChecks(in scenario: ScenarioRecord) async {
    switch await callPage(Self.realAppChecksBody) {
    case .success(let value):
      guard let json = value as? String,
            let data = json.data(using: .utf8),
            let results = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
        scenario.checks.append(ProbeCheck(name: "realapp-checks", ok: false, detail: "unexpected result \(value)"))
        return
      }
      for result in results {
        scenario.checks.append(ProbeCheck(
          name: result["name"] as? String ?? "unnamed",
          ok: result["ok"] as? Bool ?? false,
          detail: result["detail"] as? String ?? ""
        ))
      }
    case .failure(let error):
      scenario.checks.append(ProbeCheck(name: "realapp-checks", ok: false, detail: error.localizedDescription))
    }
  }

  /// Uncaught errors, unhandled rejections, CSP violations, failed resources and worker errors of the web app
  private func recordRealAppErrors(in scenario: ScenarioRecord) {
    let errorKinds: Set<String> = [
      "uncaught", "unhandledrejection", "csp", "resource-error", "worker-error", "navigation-error",
      "web-process-terminated",
    ]
    let errors = scenario.events.filter { errorKinds.contains($0.kind) }
    scenario.checks.append(ProbeCheck(
      name: "realapp-no-uncaught-errors",
      ok: errors.isEmpty,
      detail: errors.isEmpty ? "none" : errors.map { "\($0.kind): \($0.text)" }.joined(separator: " | ")
    ))

    let consoleErrors = scenario.events.filter { $0.kind == "console-error" }
    scenario.checks.append(ProbeCheck(
      name: "info-realapp-console-errors",
      ok: consoleErrors.isEmpty,
      detail: consoleErrors.isEmpty ? "none" : consoleErrors.map { $0.text }.joined(separator: " | ")
    ))

    let workerEvents = scenario.events.filter { $0.kind.hasPrefix("worker-") }
    scenario.checks.append(ProbeCheck(
      name: "info-realapp-workers",
      ok: !workerEvents.contains { $0.kind == "worker-error" },
      detail: workerEvents.map { "\($0.kind) \($0.text)" }.joined(separator: " | ")
    ))
  }

  private func beginScenario(_ name: String, origin: ProbeOrigin, url: URL) -> ScenarioRecord {
    let scenario = ScenarioRecord(name: name, origin: origin.label, url: url.absoluteString, startedAt: elapsed)
    scenarios.append(scenario)
    currentScenario = scenario
    schemeHandler.scenarioName = "\(name)-\(origin.label)"
    logger.notice("Scenario \(name, privacy: .public) over \(origin.label, privacy: .public)")

    // The URL check the app uses for its navigation decisions
    let isAppURL = origin.label == Self.customOriginLabel ? AppSchemeHandler.isAppURL(url) : LocalServer.isAppURL(url)
    scenario.checks.append(ProbeCheck(name: "native-is-app-url", ok: isAppURL, detail: url.absoluteString))
    return scenario
  }

  private func endScenario(_ scenario: ScenarioRecord) async {
    scenario.snapshot = await saveSnapshot(named: "\(scenario.name)-\(scenario.origin).png")
    scenario.finishedAt = elapsed
    currentScenario = nil
    pageWaiter = nil
  }

  private func waitForPageDone(timeout: TimeInterval) async -> Bool {
    await withCheckedContinuation { continuation in
      let waiter = OnceWaiter(continuation)
      pageWaiter = waiter
      DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
        waiter.resume(false)
      }
    }
  }

  private func callPage(_ functionBody: String) async -> Result<Any, Error> {
    await withCheckedContinuation { continuation in
      webView.callAsyncJavaScript(functionBody, arguments: [:], in: nil, in: .page) { result in
        continuation.resume(returning: result)
      }
    }
  }

  private func evaluateBoolean(_ functionBody: String) async -> Bool {
    guard case .success(let value) = await callPage(functionBody) else {
      return false
    }
    return value as? Bool ?? false
  }

  private func saveSnapshot(named fileName: String) async -> String? {
    let file = outputDirectory.appendingPathComponent(fileName)
    return await withCheckedContinuation { continuation in
      webView.takeSnapshot(with: nil) { image, _ in
        guard let data = image?.pngData(), (try? data.write(to: file)) != nil else {
          continuation.resume(returning: nil)
          return
        }
        continuation.resume(returning: fileName)
      }
    }
  }

  /// How Settings-like listings see the data of both origins, which matters for removing the data of one of them
  private func fetchDataRecords() async -> [DataRecordInfo] {
    await withCheckedContinuation { continuation in
      WKWebsiteDataStore.default().fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
        continuation.resume(returning: records.map { record in
          DataRecordInfo(displayName: record.displayName, dataTypes: record.dataTypes.sorted())
        })
      }
    }
  }

  private func recordEvent(_ kind: String, _ text: String) {
    currentScenario?.events.append(ProbeEvent(time: elapsed, kind: kind, text: text))
  }

  private func recordNavigationError(_ error: Error) {
    let nsError = error as NSError
    let isExpected = (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
      || (nsError.domain == Self.webKitErrorDomain && nsError.code == Self.frameLoadInterruptedCode)
    recordEvent(
      isExpected ? "navigation-note" : "navigation-error",
      "\(nsError.domain) \(nsError.code) \(nsError.localizedDescription)"
    )
  }

  /// Checks that the origin WebKit reports for the page's messages passes the app's own origin check, which
  /// `NativeBridge` and the media capture prompt rely on
  private func recordMessageOrigin(of frame: WKFrameInfo, in scenario: ScenarioRecord) {
    guard frame.isMainFrame, !scenario.hasMessageOrigin else {
      return
    }
    scenario.hasMessageOrigin = true
    let origin = frame.securityOrigin
    let isAppOrigin = scenario.origin == Self.customOriginLabel
      ? AppSchemeHandler.isAppOrigin(scheme: origin.protocol, host: origin.host, port: origin.port)
      : LocalServer.isAppOrigin(scheme: origin.protocol, host: origin.host, port: origin.port)
    scenario.checks.append(ProbeCheck(
      name: "native-message-origin",
      ok: isAppOrigin,
      detail: "\(origin.protocol)://\(origin.host) port \(origin.port)"
    ))
  }

  private func callPageDownloadDone(name: String, size: Int) {
    let script = "void window.__probeDownloadDone?.(\(Self.makeJavaScriptString(name)), \(size))"
    webView.evaluateJavaScript(script) { _, error in
      if let error {
        logger.error("Could not report a download: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func prepareOutputDirectory() {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: outputDirectory)
    do {
      try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    } catch {
      logger.error("Could not create the output folder: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func writeReport(dataRecords: [DataRecordInfo]) {
    let device = UIDevice.current
    let formatter = ISO8601DateFormatter()
    let report = ProbeReport(
      phase: phase.rawValue,
      runId: runId,
      systemName: device.systemName,
      systemVersion: device.systemVersion,
      model: device.model,
      userAgent: userAgent,
      isSchemeHandledByWebKit: WKWebView.handlesURLScheme(AppSchemeHandler.scheme),
      startedAt: formatter.string(from: startDate),
      finishedAt: formatter.string(from: Date()),
      scenarios: scenarios,
      schemeRequests: schemeHandler.records,
      dataRecords: dataRecords
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    do {
      try encoder.encode(report).write(to: outputDirectory.appendingPathComponent(Self.reportFileName))
    } catch {
      logger.error("Could not write the report: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func writeDoneMarker() {
    let marker = Data("{\"phase\":\"\(phase.rawValue)\",\"scenarios\":\(scenarios.count)}".utf8)
    do {
      try marker.write(to: outputDirectory.appendingPathComponent(Self.doneFileName))
    } catch {
      logger.error("Could not write the done marker: \(error.localizedDescription, privacy: .public)")
    }
  }
}

extension ProbeViewController: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let scenario = currentScenario else {
      return
    }
    if message.name == Self.bridgeHandlerName {
      scenario.events.append(ProbeEvent(time: elapsed, kind: "bridge", text: Self.describe(message.body)))
      return
    }
    guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
      return
    }

    recordMessageOrigin(of: message.frameInfo, in: scenario)
    switch type {
    case "check":
      scenario.checks.append(ProbeCheck(
        name: body["name"] as? String ?? "unnamed",
        ok: body["ok"] as? Bool ?? false,
        detail: body["detail"] as? String ?? ""
      ))
    case "done":
      // A page that the next scenario replaced must not end that scenario
      guard message.frameInfo.isMainFrame,
            message.frameInfo.request.url?.path == URL(string: scenario.url)?.path else {
        return
      }
      pageWaiter?.resume(true)
      pageWaiter = nil
    default:
      let kind = (body["kind"] as? String).map { "\(type)-\($0)" } ?? type
      scenario.events.append(ProbeEvent(time: elapsed, kind: kind, text: body["text"] as? String ?? Self.describe(body)))
    }
  }
}

extension ProbeViewController: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    if navigationAction.shouldPerformDownload {
      decisionHandler(.download)
      return
    }
    let request = navigationAction.request
    if navigationAction.targetFrame?.isMainFrame == false, let url = request.url {
      // Pages served from a custom scheme send no `Referer`, which some embeds require
      let referer = request.value(forHTTPHeaderField: "Referer") ?? "(none)"
      recordEvent("frame-navigation", "\(url.absoluteString) Referer: \(referer)")
      if url.host == Self.referrerProbeHost {
        currentScenario?.checks.append(ProbeCheck(name: "info-iframe-referer", ok: referer != "(none)", detail: referer))
        decisionHandler(.cancel)
        return
      }
    }
    decisionHandler(.allow)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
  ) {
    decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
  }

  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    download.delegate = self
  }

  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    download.delegate = self
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    recordNavigationError(error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    recordNavigationError(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    recordEvent("web-process-terminated", "the web content process ended")
  }
}

extension ProbeViewController: WKUIDelegate {
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    recordEvent("window-open", navigationAction.request.url?.absoluteString ?? "")
    return nil
  }

  func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
  ) {
    // The probe only checks that capture is available and never records
    recordEvent("media-capture-request", "\(origin.protocol)://\(origin.host)")
    decisionHandler(.deny)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor () -> Void
  ) {
    recordEvent("alert", message)
    completionHandler()
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor (Bool) -> Void
  ) {
    recordEvent("confirm", message)
    completionHandler(false)
  }
}

extension ProbeViewController: WKDownloadDelegate {
  func download(
    _ download: WKDownload,
    decideDestinationUsing response: URLResponse,
    suggestedFilename: String,
    completionHandler: @escaping @MainActor (URL?) -> Void
  ) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      recordEvent("download-error", error.localizedDescription)
      completionHandler(nil)
      return
    }
    let fileName = suggestedFilename.isEmpty ? "download" : suggestedFilename.replacingOccurrences(of: "/", with: "_")
    let destination = directory.appendingPathComponent(fileName, isDirectory: false)
    downloadDestinations[download] = destination
    completionHandler(destination)
  }

  func downloadDidFinish(_ download: WKDownload) {
    guard let destination = downloadDestinations.removeValue(forKey: download) else {
      return
    }
    let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
    recordEvent("download", "\(destination.lastPathComponent) \(size) bytes")
    callPageDownloadDone(name: destination.lastPathComponent, size: size)
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    downloadDestinations.removeValue(forKey: download)
    recordEvent("download-error", error.localizedDescription)
    callPageDownloadDone(name: "failed: \(error.localizedDescription)", size: -1)
  }
}

/// Forwards script messages to the controller without retaining it, since `WKUserContentController` retains its
/// handlers
private final class WeakMessageHandler: NSObject {
  weak var target: WKScriptMessageHandler?
}

extension WeakMessageHandler: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(userContentController, didReceive: message)
  }
}
