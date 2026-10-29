import os
import UIKit
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "WebView")

private enum Strings {
  static let ok = NSLocalizedString("alert.ok", value: "OK", comment: "Button that accepts a web page dialog")
  static let cancel = NSLocalizedString("alert.cancel", value: "Cancel", comment: "Button that dismisses a web page dialog")
  static let startupError = NSLocalizedString(
    "startup.error",
    value: "Liquidgram could not start. Close the app and open it again.",
    comment: "Shown when the bundled web app does not load"
  )
}

/// Shows the bundled web app full screen. The page extends under the status bar and the home indicator and
/// lays itself out with `env(safe-area-inset-*)`, because `index.html` sets `viewport-fit=cover`.
final class WebViewController: UIViewController {
  /// Matches the launch screen until the page draws
  static let backgroundColor = UIColor(named: "LaunchBackground") ?? .systemBackground

  private static let applicationName = "Liquidgram"
  private static let startupTimeout: TimeInterval = 10
  private static let initialRetryDelay: TimeInterval = 1
  private static let maxRetryDelay: TimeInterval = 8
  private static let externalSchemes: Set<String> = ["http", "https", "mailto", "tel", "tg"]
  private static let embeddedSchemes: Set<String> = ["http", "https"]
  private static let downloadSchemes: Set<String> = ["blob", "data"]
  private static let fallbackFileName = "download"
  // Relative luminance weights of sRGB (Rec. 709) and the level below which the theme color counts as dark
  private static let luminanceWeights: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0.2126, 0.7152, 0.0722)
  private static let darkLuminance: CGFloat = 0.5
  private static let downloadsDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("Downloads", isDirectory: true)

  private let server: LocalServer
  private let bridge: NativeBridge
  private let webView: WKWebView
  private var themeColorObservation: NSKeyValueObservation?
  private var statusBarStyle = UIStatusBarStyle.default
  private var hasLoadedApp = false
  private var needsReloadOnActivation = false
  private var isRetryScheduled = false
  private var retryDelay = WebViewController.initialRetryDelay
  private var lastLoadError: String?
  private var startupErrorLabel: UILabel?
  private var downloadDestinations: [WKDownload: URL] = [:]
  private var pendingShareURLs: [URL] = []

  init(server: LocalServer, bridge: NativeBridge) {
    let webView = WebViewController.makeWebView(bridge: bridge)
    bridge.webView = webView
    self.server = server
    self.bridge = bridge
    self.webView = webView
    super.init(nibName: nil, bundle: nil)
    // Files shared after earlier downloads are no longer needed
    try? FileManager.default.removeItem(at: Self.downloadsDirectory)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    statusBarStyle
  }

  override func loadView() {
    let containerView = UIView()
    containerView.backgroundColor = Self.backgroundColor
    webView.frame = containerView.bounds
    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    containerView.addSubview(webView)
    view = containerView
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    webView.navigationDelegate = self
    webView.uiDelegate = self

    // The page sets `<meta name="theme-color">` for its light and dark themes
    themeColorObservation = webView.observe(\.themeColor, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.updateStatusBarStyle()
      }
    }

    // The injected state needs the notification permission before the first page starts
    bridge.refreshPermission { [weak self] in
      self?.loadApp()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.startupTimeout) { [weak self] in
      self?.showStartupErrorIfNeeded()
    }
  }

  /// Reloads a page whose web process iOS ended while the app was in the background
  func handleDidBecomeActive() {
    guard needsReloadOnActivation else {
      return
    }
    needsReloadOnActivation = false
    reloadApp()
  }

  private static func makeWebView(bridge: NativeBridge) -> WKWebView {
    let userContentController = WKUserContentController()
    bridge.register(in: userContentController)

    let configuration = WKWebViewConfiguration()
    configuration.userContentController = userContentController
    configuration.websiteDataStore = .default()
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    // Appended to the default user agent, which stays otherwise unchanged
    configuration.applicationNameForUserAgent = applicationName

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.isOpaque = false
    webView.backgroundColor = backgroundColor
    webView.scrollView.backgroundColor = backgroundColor
    // The page handles the safe area itself through `env(safe-area-inset-*)`
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.scrollView.bounces = false
    webView.allowsBackForwardNavigationGestures = false
    webView.allowsLinkPreview = false
    if #available(iOS 16.4, *) {
      webView.isInspectable = true
    }
    return webView
  }

  /// Picks status bar text that stays readable over the page's theme color
  private static func makeStatusBarStyle(for themeColor: UIColor?) -> UIStatusBarStyle {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard let themeColor, themeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return .default
    }
    let luminance = luminanceWeights.red * red + luminanceWeights.green * green + luminanceWeights.blue * blue
    return luminance < darkLuminance ? .lightContent : .darkContent
  }

  /// Makes a file name from the page safe to create in the downloads folder
  private static func makeSafeFileName(_ suggestedFileName: String) -> String {
    let fileName = suggestedFileName
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: ":", with: "_")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fileName.isEmpty, fileName != ".", fileName != ".." else {
      return fallbackFileName
    }
    return fileName
  }

  private func updateStatusBarStyle() {
    let style = Self.makeStatusBarStyle(for: webView.themeColor)
    guard style != statusBarStyle else {
      return
    }
    statusBarStyle = style
    setNeedsStatusBarAppearanceUpdate()
  }

  private func loadApp() {
    server.whenReady { [weak self] in
      self?.webView.load(URLRequest(url: LocalServer.appURL))
    }
  }

  /// Reloads the current page of the app, keeping its route, or loads the app if it is not shown
  private func reloadApp() {
    server.whenReady { [weak self] in
      guard let self else {
        return
      }
      if let url = self.webView.url, LocalServer.isAppURL(url) {
        self.webView.reload()
      } else {
        self.webView.load(URLRequest(url: LocalServer.appURL))
      }
    }
  }

  private func scheduleRetry() {
    guard !isRetryScheduled else {
      return
    }
    isRetryScheduled = true
    let delay = retryDelay
    retryDelay = min(retryDelay * 2, Self.maxRetryDelay)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else {
        return
      }
      self.isRetryScheduled = false
      self.server.start()
      self.reloadApp()
    }
  }

  /// Explains a failed start on screen, since the device keeps no log the user can reach. Loads that
  /// succeed later remove the message.
  private func showStartupErrorIfNeeded() {
    guard !hasLoadedApp else {
      return
    }
    server.fetchFailure { [weak self] serverFailure in
      guard let self, !self.hasLoadedApp, self.startupErrorLabel == nil,
            let details = serverFailure ?? self.lastLoadError else {
        return
      }

      let label = UILabel()
      label.translatesAutoresizingMaskIntoConstraints = false
      label.numberOfLines = 0
      label.textAlignment = .center
      label.font = .preferredFont(forTextStyle: .body)
      label.adjustsFontForContentSizeCategory = true
      label.textColor = .label
      label.text = Strings.startupError + "\n\n" + details
      self.view.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.leadingAnchor),
        label.trailingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.trailingAnchor),
        label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      ])
      self.startupErrorLabel = label
    }
  }

  /// Only http(s), mail, phone and Telegram links leave the app, so a page cannot launch arbitrary apps
  private func openExternally(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(), Self.externalSchemes.contains(scheme) else {
      logger.info("Ignored a link with an unsupported scheme")
      return
    }
    UIApplication.shared.open(url, options: [:]) { isOpened in
      if !isOpened {
        logger.info("No app opened a link")
      }
    }
  }

  /// The controller to present a dialog from, or `nil` while the page is not on screen
  private func findModalPresenter() -> UIViewController? {
    guard viewIfLoaded?.window != nil else {
      return nil
    }
    var presenter: UIViewController = self
    while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
      presenter = presented
    }
    return presenter
  }

  /// Offers finished downloads in the share sheet, which has Save to Files and Save to Photos. Downloads
  /// that finish while the sheet is open wait for it to close.
  private func presentPendingShares() {
    guard !pendingShareURLs.isEmpty, let presenter = findModalPresenter(),
          !(presenter is UIActivityViewController) else {
      return
    }

    let activityController = UIActivityViewController(activityItems: pendingShareURLs, applicationActivities: nil)
    pendingShareURLs.removeAll()
    activityController.completionWithItemsHandler = { [weak self] _, _, _, _ in
      self?.presentPendingShares()
    }
    // iPad shows the sheet as a popover, which needs an anchor
    if let popover = activityController.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    presenter.present(activityController, animated: true)
  }
}

extension WebViewController: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    if navigationAction.shouldPerformDownload {
      decisionHandler(.download)
      return
    }
    // Links that ask for a new window go through `webView(_:createWebViewWith:for:windowFeatures:)`
    guard let targetFrame = navigationAction.targetFrame else {
      decisionHandler(.allow)
      return
    }
    guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
      decisionHandler(.cancel)
      return
    }

    if LocalServer.isAppURL(url) || scheme == "about" {
      decisionHandler(.allow)
    } else if Self.downloadSchemes.contains(scheme) {
      // The app itself must never be replaced by a file
      decisionHandler(targetFrame.isMainFrame ? .download : .allow)
    } else if !targetFrame.isMainFrame && Self.embeddedSchemes.contains(scheme) {
      // Frames inside the page, such as bot web apps and video embeds, load in place
      decisionHandler(.allow)
    } else {
      openExternally(url)
      decisionHandler(.cancel)
    }
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

  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    guard let url = webView.url, LocalServer.isAppURL(url) else {
      return
    }
    hasLoadedApp = true
    lastLoadError = nil
    retryDelay = Self.initialRetryDelay
    startupErrorLabel?.removeFromSuperview()
    startupErrorLabel = nil
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    let nsError = error as NSError
    // Cancelled loads, including navigations that became downloads, need no retry
    guard nsError.domain == NSURLErrorDomain, nsError.code != NSURLErrorCancelled else {
      return
    }
    logger.error("The app did not load: \(nsError.localizedDescription, privacy: .public)")
    lastLoadError = nsError.localizedDescription
    scheduleRetry()
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    logger.error("The web content process ended")
    if UIApplication.shared.applicationState == .active {
      reloadApp()
    } else {
      needsReloadOnActivation = true
    }
  }
}

extension WebViewController: WKUIDelegate {
  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    // The app has a single window: links for new windows open in other apps, and files are downloaded
    guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
      return nil
    }
    if Self.downloadSchemes.contains(scheme) {
      webView.startDownload(using: navigationAction.request) { [weak self] download in
        download.delegate = self
      }
    } else if !LocalServer.isAppURL(url) {
      openExternally(url)
    }
    return nil
  }

  func webView(
    _ webView: WKWebView,
    requestMediaCapturePermissionFor origin: WKSecurityOrigin,
    initiatedByFrame frame: WKFrameInfo,
    type: WKMediaCaptureType,
    decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
  ) {
    // The app's own page skips WebKit's prompt for every capture; iOS still asks once for the camera and
    // the microphone. Other frames, such as bot web apps, keep the prompt.
    let isApp = frame.isMainFrame
      && LocalServer.isAppOrigin(scheme: origin.protocol, host: origin.host, port: origin.port)
    decisionHandler(isApp ? .grant : .prompt)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptAlertPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor () -> Void
  ) {
    guard let presenter = findModalPresenter() else {
      completionHandler()
      return
    }
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: Strings.ok, style: .default) { _ in
      completionHandler()
    })
    presenter.present(alert, animated: true)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptConfirmPanelWithMessage message: String,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor (Bool) -> Void
  ) {
    guard let presenter = findModalPresenter() else {
      completionHandler(false)
      return
    }
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: Strings.cancel, style: .cancel) { _ in
      completionHandler(false)
    })
    alert.addAction(UIAlertAction(title: Strings.ok, style: .default) { _ in
      completionHandler(true)
    })
    presenter.present(alert, animated: true)
  }

  func webView(
    _ webView: WKWebView,
    runJavaScriptTextInputPanelWithPrompt prompt: String,
    defaultText: String?,
    initiatedByFrame frame: WKFrameInfo,
    completionHandler: @escaping @MainActor (String?) -> Void
  ) {
    guard let presenter = findModalPresenter() else {
      completionHandler(nil)
      return
    }
    let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
    alert.addTextField { textField in
      textField.text = defaultText
    }
    alert.addAction(UIAlertAction(title: Strings.cancel, style: .cancel) { _ in
      completionHandler(nil)
    })
    alert.addAction(UIAlertAction(title: Strings.ok, style: .default) { [weak alert] _ in
      completionHandler(alert?.textFields?.first?.text ?? "")
    })
    presenter.present(alert, animated: true)
  }
}

extension WebViewController: WKDownloadDelegate {
  func download(
    _ download: WKDownload,
    decideDestinationUsing response: URLResponse,
    suggestedFilename: String,
    completionHandler: @escaping @MainActor (URL?) -> Void
  ) {
    // A new folder per download keeps the suggested name and never collides with an existing file
    let directory = Self.downloadsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      logger.error("Could not create a download folder: \(error.localizedDescription, privacy: .public)")
      completionHandler(nil)
      return
    }
    let destination = directory.appendingPathComponent(Self.makeSafeFileName(suggestedFilename), isDirectory: false)
    downloadDestinations[download] = destination
    completionHandler(destination)
  }

  func downloadDidFinish(_ download: WKDownload) {
    guard let destination = downloadDestinations.removeValue(forKey: download) else {
      return
    }
    pendingShareURLs.append(destination)
    presentPendingShares()
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    downloadDestinations.removeValue(forKey: download)
    logger.error("A download failed: \(error.localizedDescription, privacy: .public)")
  }
}
