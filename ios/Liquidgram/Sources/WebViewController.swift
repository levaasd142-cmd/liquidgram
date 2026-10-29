import os
import SafariServices
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
  static let noAppForLink = NSLocalizedString(
    "link.noApp",
    value: "No app on this device can open this link.",
    comment: "Shown when the user taps a link of a kind that no installed app opens, such as a TON wallet link"
  )
  static let locationRequest = NSLocalizedString(
    "location.request",
    value: "Allow “%@” to use your location?",
    comment: "Title of the question before a site inside the app, such as a bot web app, gets the location; %@ is its host"
  )
  static let allow = NSLocalizedString("alert.allow", value: "Allow", comment: "Button that grants a site's request")
  static let dontAllow = NSLocalizedString(
    "alert.dontAllow",
    value: "Don’t Allow",
    comment: "Button that refuses a site's request"
  )
}

/// Shows the bundled web app. The web view starts below the status bar and ends at the bottom of the screen, or at the
/// top of a docked keyboard: the web app lays itself out like in a browser tab and uses `env(safe-area-inset-*)` only
/// for the home indicator. The strip under the status bar has the page's `theme-color`.
final class WebViewController: UIViewController {
  /// Matches the launch screen until the page sets its theme color
  static let backgroundColor = UIColor(named: "LaunchBackground") ?? .systemBackground

  /// The app's screens stay upright on iPhone, where the web app's layout is made for portrait. Full-screen video,
  /// which WebKit shows in a window of its own, still turns, see `AppDelegate`.
  static var supportedOrientations: UIInterfaceOrientationMask {
    UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .all
  }

  private static let applicationName = "Liquidgram"
  private static let startupTimeout: TimeInterval = 10
  private static let initialRetryDelay: TimeInterval = 1
  private static let maxRetryDelay: TimeInterval = 8
  /// Schemes that any link, also one a script opens, may leave the app with. A tapped link may use other schemes too.
  private static let externalSchemes: Set<String> = ["http", "https", "mailto", "tel"]
  /// Schemes that never leave the app, even from a tapped link
  private static let blockedSchemes: Set<String> = ["about", "blob", "data", "file", "javascript"]
  /// Telegram links of these schemes open in the web app, the way links in messages do
  private static let telegramSchemes: Set<String> = ["tg", "liquidgram"]
  private static let webSchemes: Set<String> = ["http", "https"]
  private static let downloadSchemes: Set<String> = ["blob", "data"]
  private static let blankPageURL = URL(string: "about:blank")!
  /// The status bar tap sentinel's content is this many times its height, so it always has room to scroll up
  private static let statusBarTapContentScale: CGFloat = 2
  private static let fallbackFileName = "download"
  // Relative luminance weights of sRGB (Rec. 709) and the level below which the theme color counts as dark
  private static let luminanceWeights: (red: CGFloat, green: CGFloat, blue: CGFloat) = (0.2126, 0.7152, 0.0722)
  private static let darkLuminance: CGFloat = 0.5
  /// Like the web app's own theme transition
  private static let themeTransitionDuration: TimeInterval = 0.2
  /// A keyboard counts as docked when it reaches the bottom of the screen and spans its width, within this distance
  private static let dockedKeyboardTolerance: CGFloat = 1
  /// The launch screen's logo fades into the page once it has drawn
  private static let launchOverlayFadeDuration: TimeInterval = 0.2
  /// Seconds to wait for the web app's first render before the launch overlay goes away anyway
  private static let firstRenderTimeout: TimeInterval = 10
  /// Seconds to wait for the web app's loading mask to go away after its first render
  private static let loadingMaskTimeout: TimeInterval = 2
  private static let firstRenderPollInterval: TimeInterval = 0.05
  /// How long after a native action asks for typing the page may raise the keyboard without a tap
  private static let scriptFocusWindow: Duration = .seconds(3)
  private static let downloadsDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("Downloads", isDirectory: true)
  /// WebKit avoids the keyboard like Safari does: it leaves the page at full height under the keyboard and scrolls
  /// the whole document to reveal the focused field, which moves every header off the screen. The app resizes the web
  /// view instead, so WebKit stops listening to these. It keeps `UIKeyboardDidShowNotification`, where it only ends
  /// its own bookkeeping of the keyboard animation.
  private static let webKitKeyboardNotifications: [Notification.Name] = [
    UIResponder.keyboardWillShowNotification,
    UIResponder.keyboardWillHideNotification,
    UIResponder.keyboardWillChangeFrameNotification,
    UIResponder.keyboardDidChangeFrameNotification,
  ]
  /// Resolves once the web app shows its first screen, and two frames later, when that screen is on the display. The
  /// web app removes the `initial` class of `<html>` in its first render, which may take up to `timeout` seconds. It
  /// then covers itself with a loading mask until it has its fonts and images, for up to `maskTimeout` seconds; the
  /// middle of the page is the app's own once the mask is gone.
  private static let firstRenderScript = """
    const wait = () => new Promise((resolve) => setTimeout(resolve, interval * 1000));
    const deadline = Date.now() + timeout * 1000;
    while (document.documentElement.classList.contains('initial') && Date.now() < deadline) {
      await wait();
    }
    const maskDeadline = Math.min(deadline, Date.now() + maskTimeout * 1000);
    const isAppInMiddle = () => Boolean(
      document.elementFromPoint(innerWidth / 2, innerHeight / 2)?.closest('#root > .Transition')
    );
    while (!isAppInMiddle() && Date.now() < maskDeadline) {
      await wait();
    }
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    """

  private let server: LocalServer
  private let bridge: NativeBridge
  private let webView: WKWebView
  /// UIKit offers a status bar tap only to a scroll view that can scroll, and the page's own scroll view never
  /// does, because the web app scrolls elements inside the page. This invisible one behind the web view takes the
  /// tap and passes it to the page.
  private let statusBarTapView = UIScrollView()
  /// The launch screen, until the page has drawn: at launch and while the page reloads after its process ended
  private let launchOverlay = LaunchOverlayView()
  private let documentScrollPin = DocumentScrollPin()
  private let scriptFocusPolicy = ScriptFocusPolicy()
  private var themeColorObservation: NSKeyValueObservation?
  private var fullscreenObservation: NSKeyValueObservation?
  private var statusBarStyle = UIStatusBarStyle.default
  /// The appearance of the page's theme color, which native views on top of the page follow
  private var pageInterfaceStyle = UIUserInterfaceStyle.unspecified
  /// The frame of the keyboard in screen coordinates while one is shown
  private var keyboardFrame: CGRect?
  /// Counts the times the launch overlay was shown, so a fade that ends late leaves a newer overlay alone
  private var launchOverlayGeneration = 0
  private var hasLoadedApp = false
  private var needsReloadOnActivation = false
  /// The page to load again once the server's port is this app's own again
  private var urlToRestore: URL?
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
    server.portConflictHandler = { [weak self] in
      self?.unloadPageForPortConflict()
    }
    bridge.willDispatchAction = { [weak self] action in
      self?.prepare(for: action)
    }
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

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    Self.supportedOrientations
  }

  override func loadView() {
    let containerView = UIView()
    containerView.backgroundColor = Self.backgroundColor

    statusBarTapView.frame = containerView.bounds
    statusBarTapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    statusBarTapView.contentInsetAdjustmentBehavior = .never
    statusBarTapView.showsVerticalScrollIndicator = false
    statusBarTapView.scrollsToTop = true
    statusBarTapView.accessibilityElementsHidden = true
    statusBarTapView.delegate = self
    containerView.addSubview(statusBarTapView)

    // `layoutWebView()` sets the frame. WebKit moves the web view into a window of its own while an element of the
    // page is full screen and back afterwards, which would drop constraints.
    webView.autoresizingMask = []
    // UIKit ignores a status bar tap while two scroll views could take it
    webView.scrollView.scrollsToTop = false
    containerView.addSubview(webView)

    launchOverlay.frame = containerView.bounds
    launchOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    containerView.addSubview(launchOverlay)
    webView.accessibilityElementsHidden = true
    view = containerView
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    layoutWebView()
    let size = statusBarTapView.bounds.size
    statusBarTapView.contentSize = CGSize(width: size.width, height: size.height * Self.statusBarTapContentScale)
    statusBarTapView.contentOffset = CGPoint(x: 0, y: size.height)
  }

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    view.setNeedsLayout()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.scrollView.delegate = documentScrollPin
    if !scriptFocusPolicy.install(in: webView) {
      logger.notice("WebKit has no input delegate; a quick action focuses the search without the keyboard")
    }

    // The page sets `<meta name="theme-color">` for its light and dark themes, and darker while it shows media
    themeColorObservation = webView.observe(\.themeColor, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.applyThemeColor(isAnimated: true)
      }
    }
    fullscreenObservation = webView.observe(\.fullscreenState, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        // The web view is back from WebKit's full-screen window, with the frame it had when it left
        self?.view.setNeedsLayout()
      }
    }
    let notificationCenter = NotificationCenter.default
    notificationCenter.addObserver(
      self,
      selector: #selector(keyboardWillChangeFrame(_:)),
      name: UIResponder.keyboardWillChangeFrameNotification,
      object: nil
    )
    notificationCenter.addObserver(
      self,
      selector: #selector(keyboardWillChangeFrame(_:)),
      name: UIResponder.keyboardWillHideNotification,
      object: nil
    )

    // The injected state needs the notification permission before the first page starts
    TestHooks.prepareForLaunch { [weak self] in
      self?.bridge.refreshPermission {
        self?.loadApp()
      }
    }
    scheduleStartupErrorCheck()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    // A full-screen controller, such as the in-app browser, took the first responder while it was shown
    focusPage()
  }

  /// Reloads a page whose web process iOS ended while the app was in the background
  func handleDidBecomeActive() {
    focusPage()
    guard needsReloadOnActivation else {
      return
    }
    needsReloadOnActivation = false
    reloadApp()
  }

  /// Makes the page the first responder. WebKit reports `document.hasFocus()` only then, and the web app pauses its
  /// animations and videos while the page has no focus, as in a background tab. Safari does this for its pages; a
  /// web view otherwise waits for the first tap. No keyboard appears while no field of the page is focused.
  func focusPage() {
    guard hasLoadedApp, presentedViewController == nil, webView.window != nil else {
      return
    }
    webView.becomeFirstResponder()
  }

  private static func makeWebView(bridge: NativeBridge) -> WKWebView {
    let userContentController = WKUserContentController()
    bridge.register(in: userContentController)

    let configuration = WKWebViewConfiguration()
    configuration.userContentController = userContentController
    configuration.websiteDataStore = .default()
    configuration.allowsInlineMediaPlayback = true
    configuration.allowsPictureInPictureMediaPlayback = true
    configuration.allowsAirPlayForMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    // WebKit's pop-up blocker drops a window that a script opens more than a second after the tap, as the web app does
    // after asking Telegram, for example for "Log in" buttons of bots and for links checked for an Instant View. No
    // window is ever created: `webView(_:createWebViewWith:for:windowFeatures:)` opens or downloads the link instead,
    // and frames of other sites still need a tapped link.
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    // The Fullscreen API, for the call screen and bot web apps. Videos of the web app keep the system player.
    configuration.preferences.isElementFullscreenEnabled = true
    // WebKit's own application name holds the `Mobile/…` token that bot web apps and embeds need to choose their
    // mobile layout, so the app's name goes after it
    configuration.applicationNameForUserAgent = [configuration.applicationNameForUserAgent, applicationName]
      .compactMap { $0 }
      .joined(separator: " ")

    let webView = AppWebView(frame: .zero, configuration: configuration)
    webView.accessibilityIdentifier = "liquidgram.webview"
    webView.isOpaque = false
    webView.backgroundColor = backgroundColor
    webView.scrollView.backgroundColor = backgroundColor
    // The web view starts below the status bar, and the page handles the other insets with `env(safe-area-inset-*)`
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    // The page is as tall as the web view and scrolls elements inside it, so the document itself never scrolls
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.bounces = false
    webView.allowsBackForwardNavigationGestures = false
    webView.allowsLinkPreview = false
    if #available(iOS 16.4, *) {
      webView.isInspectable = true
    }
    for name in webKitKeyboardNotifications {
      NotificationCenter.default.removeObserver(webView, name: name, object: nil)
    }
    return webView
  }

  /// Picks status bar text that stays readable over the page's theme color
  private static func makeStatusBarStyle(for themeColor: UIColor?) -> UIStatusBarStyle {
    switch makeInterfaceStyle(for: themeColor) {
    case .dark:
      return .lightContent
    case .light:
      return .darkContent
    default:
      return .default
    }
  }

  /// Dark for a dark theme color, light for a light one
  private static func makeInterfaceStyle(for themeColor: UIColor?) -> UIUserInterfaceStyle {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    guard let themeColor, themeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
      return .unspecified
    }
    let luminance = luminanceWeights.red * red + luminanceWeights.green * green + luminanceWeights.blue * blue
    return luminance < darkLuminance ? .dark : .light
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

  /// Whether a frame is the main frame of the app's own page, rather than a frame of another site inside it
  private static func isAppMainFrame(_ frame: WKFrameInfo?) -> Bool {
    guard let frame, frame.isMainFrame else {
      return false
    }
    let origin = frame.securityOrigin
    return LocalServer.isAppOrigin(scheme: origin.protocol, host: origin.host, port: origin.port)
  }

  /// The web view fills the view below the status bar and above a docked keyboard
  private func layoutWebView() {
    // WebKit has the web view in its own window while an element of the page is full screen
    guard webView.superview === view, webView.fullscreenState == .notInFullscreen else {
      return
    }
    let bounds = view.bounds
    let top = min(bounds.minY + view.safeAreaInsets.top, bounds.maxY)
    let bottom = max(top, bounds.maxY - makeKeyboardOverlap())
    let frame = CGRect(x: bounds.minX, y: top, width: bounds.width, height: bottom - top)
    if webView.frame != frame {
      webView.frame = frame
    }
  }

  /// The height at the bottom of the view that the keyboard covers. A keyboard that does not reach the bottom of the
  /// screen across its whole width, such as a floating or split keyboard on iPad, leaves the layout alone.
  private func makeKeyboardOverlap() -> CGFloat {
    guard let keyboardFrame, !keyboardFrame.isEmpty, let screen = view.window?.windowScene?.screen else {
      return 0
    }
    // The frame is from before a rotation until the keyboard reports its new one
    let screenBounds = screen.bounds
    let isDocked = keyboardFrame.maxY >= screenBounds.maxY - Self.dockedKeyboardTolerance
      && keyboardFrame.width >= screenBounds.width - Self.dockedKeyboardTolerance
    guard isDocked else {
      return 0
    }
    let frameInView = view.convert(keyboardFrame, from: screen.coordinateSpace)
    return max(0, view.bounds.maxY - frameInView.minY)
  }

  /// Ends the web view at the top of the keyboard, moving with it. The page gets a shorter viewport, as if the window
  /// had shrunk, so its headers stay where they are and its bottom bar rests on the keyboard.
  @objc private func keyboardWillChangeFrame(_ notification: Notification) {
    guard let userInfo = notification.userInfo, viewIfLoaded?.window != nil else {
      return
    }
    let frame = notification.name == UIResponder.keyboardWillHideNotification
      ? nil
      : (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
    let previousOverlap = makeKeyboardOverlap()
    keyboardFrame = frame
    guard makeKeyboardOverlap() != previousOverlap else {
      return
    }
    view.setNeedsLayout()

    let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0
    guard duration > 0 else {
      view.layoutIfNeeded()
      return
    }
    // The keyboard's curve is not one of `UIView.AnimationCurve`, but `UIView.AnimationOptions` takes it shifted
    let curve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue
      ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: [.beginFromCurrentState, UIView.AnimationOptions(rawValue: curve << 16)],
      animations: {
        self.view.layoutIfNeeded()
      }
    )
  }

  /// Paints the strip under the status bar and the background behind the keyboard in the page's theme color, picks
  /// readable status bar text, and gives the keyboard and dialogs the page's appearance. The page itself keeps the
  /// system appearance, which its automatic theme follows.
  private func applyThemeColor(isAnimated: Bool) {
    let themeColor = webView.themeColor
    let backgroundColor = themeColor ?? Self.backgroundColor
    let style = Self.makeStatusBarStyle(for: themeColor)
    pageInterfaceStyle = Self.makeInterfaceStyle(for: themeColor)
    // WebKit's content view, the first responder for the page's fields, is inside the scroll view, so the keyboard
    // follows this. The page's `prefers-color-scheme` follows the web view itself.
    webView.scrollView.overrideUserInterfaceStyle = pageInterfaceStyle

    let changes = {
      self.view.backgroundColor = backgroundColor
      self.webView.backgroundColor = backgroundColor
      self.webView.scrollView.backgroundColor = backgroundColor
      if style != self.statusBarStyle {
        self.statusBarStyle = style
        self.setNeedsStatusBarAppearanceUpdate()
      }
    }
    if isAnimated && hasLoadedApp {
      UIView.animate(withDuration: Self.themeTransitionDuration, animations: changes)
    } else {
      changes()
    }
  }

  /// Native actions that need the web view's help
  private func prepare(for action: NativeAction) {
    // The search field gets the keyboard, although no tap focuses it
    if action == .openSearch {
      scriptFocusPolicy.allowKeyboard(for: Self.scriptFocusWindow)
    }
  }

  private func showLaunchOverlay() {
    launchOverlayGeneration += 1
    launchOverlay.layer.removeAllAnimations()
    launchOverlay.alpha = 1
    launchOverlay.isHidden = false
    webView.accessibilityElementsHidden = true
  }

  /// Fades the launch screen into the page once the web app has drawn its first screen
  private func hideLaunchOverlayAfterFirstRender() {
    guard !launchOverlay.isHidden else {
      return
    }
    let generation = launchOverlayGeneration
    webView.callAsyncJavaScript(
      Self.firstRenderScript,
      arguments: [
        "timeout": Self.firstRenderTimeout,
        "maskTimeout": Self.loadingMaskTimeout,
        "interval": Self.firstRenderPollInterval,
      ],
      in: nil,
      in: .defaultClient
    ) { [weak self] result in
      if case .failure(let error) = result {
        logger.debug("Could not wait for the first render: \(error.localizedDescription, privacy: .public)")
      }
      self?.fadeOutLaunchOverlay(generation: generation)
    }
  }

  private func fadeOutLaunchOverlay(generation: Int) {
    guard generation == launchOverlayGeneration, !launchOverlay.isHidden else {
      return
    }
    // The page takes touches from now on, so VoiceOver and UI tests may reach it
    webView.accessibilityElementsHidden = false
    UIAccessibility.post(notification: .screenChanged, argument: nil)
    UIView.animate(
      withDuration: Self.launchOverlayFadeDuration,
      animations: {
        self.launchOverlay.alpha = 0
      },
      completion: { _ in
        guard generation == self.launchOverlayGeneration else {
          return
        }
        self.launchOverlay.isHidden = true
      }
    )
  }

  private func loadApp() {
    server.whenReady { [weak self] in
      self?.webView.load(URLRequest(url: LocalServer.appURL))
    }
  }

  /// Reloads the current page of the app, keeping its route, or loads the app if it is not shown. Like the first
  /// load, it waits until connections to the port reach this app's own server.
  private func reloadApp() {
    server.whenReady { [weak self] in
      guard let self else {
        return
      }
      if let url = self.urlToRestore {
        self.urlToRestore = nil
        self.webView.load(URLRequest(url: url))
      } else if let url = self.webView.url, LocalServer.isAppURL(url) {
        self.webView.reload()
      } else {
        self.webView.load(URLRequest(url: LocalServer.appURL))
      }
    }
  }

  /// Another process holds the server's port, so the page's next request could load that process's script under
  /// the app's origin. The page gives way to a blank one and comes back once the port is the app's own again.
  private func unloadPageForPortConflict() {
    guard let url = webView.url, LocalServer.isAppURL(url) else {
      return
    }
    logger.error("Another app holds the server's port; the page waits until the app has it again")
    urlToRestore = url
    webView.load(URLRequest(url: Self.blankPageURL))
    hasLoadedApp = false
    scheduleStartupErrorCheck()
    reloadApp()
  }

  private func scheduleStartupErrorCheck() {
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.startupTimeout) { [weak self] in
      self?.showStartupErrorIfNeeded()
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
      label.accessibilityIdentifier = "liquidgram.startupError"
      self.view.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.leadingAnchor),
        label.trailingAnchor.constraint(equalTo: self.view.layoutMarginsGuide.trailingAnchor),
        label.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
      ])
      self.startupErrorLabel = label
    }
  }

  /// Opens a link that leaves the page. Telegram links go to the web app, which handles them like links in messages,
  /// rather than to the official Telegram app. Web links open in the in-app browser unless the user turned it off.
  /// Other schemes open other apps: mail and phone links always, any other app only for a tapped link, so a page
  /// cannot launch apps by itself.
  private func openExternally(_ url: URL, isTapped: Bool) {
    guard let scheme = url.scheme?.lowercased() else {
      return
    }
    if Self.telegramSchemes.contains(scheme) {
      if let action = NativeAction(url: url) {
        bridge.perform(action)
      }
      return
    }
    guard Self.externalSchemes.contains(scheme) || (isTapped && !Self.blockedSchemes.contains(scheme)) else {
      logger.info("Ignored a link with an unsupported scheme")
      return
    }
    guard Self.webSchemes.contains(scheme), NativeSettings.isInAppBrowserEnabled else {
      openInOtherApp(url, isTapped: isTapped)
      return
    }
    // A link that an installed app claims as a universal link, such as a YouTube video, opens in that app
    UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { [weak self] isOpened in
      if !isOpened {
        self?.presentInAppBrowser(url)
      }
    }
  }

  /// Opens a link in the app that handles it. A tapped link that no app handles says so instead of doing nothing.
  private func openInOtherApp(_ url: URL, isTapped: Bool) {
    UIApplication.shared.open(url, options: [:]) { [weak self] isOpened in
      guard !isOpened else {
        return
      }
      logger.info("No app opened a link")
      if isTapped {
        self?.presentNoAppAlert()
      }
    }
  }

  private func presentNoAppAlert() {
    guard let presenter = findModalPresenter() else {
      return
    }
    let alert = UIAlertController(title: nil, message: Strings.noAppForLink, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: Strings.ok, style: .default))
    present(alert, from: presenter)
  }

  /// Shows a web page in Safari's view controller. It uses the user's Safari cookies and AutoFill and shares no
  /// data with the app's web view.
  private func presentInAppBrowser(_ url: URL) {
    guard let presenter = findModalPresenter() else {
      openInOtherApp(url, isTapped: false)
      return
    }
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = false
    let controller = SFSafariViewController(url: url, configuration: configuration)
    controller.dismissButtonStyle = .close
    present(controller, from: presenter)
  }

  /// Presents a controller over the page in the page's appearance
  private func present(_ controller: UIViewController, from presenter: UIViewController) {
    controller.overrideUserInterfaceStyle = pageInterfaceStyle
    presenter.present(controller, animated: true)
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
      self?.focusPage()
    }
    // iPad shows the sheet as a popover, which needs an anchor
    if let popover = activityController.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    present(activityController, from: presenter)
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
    } else if !targetFrame.isMainFrame && Self.webSchemes.contains(scheme) {
      // Frames inside the page, such as bot web apps and video embeds, load in place
      decisionHandler(.allow)
    } else {
      openExternally(url, isTapped: navigationAction.navigationType == .linkActivated)
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
    bridge.pageDidCommit()
    guard let url = webView.url, LocalServer.isAppURL(url) else {
      return
    }
    hasLoadedApp = true
    lastLoadError = nil
    retryDelay = Self.initialRetryDelay
    startupErrorLabel?.removeFromSuperview()
    startupErrorLabel = nil
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let url = webView.url, LocalServer.isAppURL(url) else {
      return
    }
    focusPage()
    hideLaunchOverlayAfterFirstRender()
    TestHooks.pageDidFinishLoading(in: webView)
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
    // The page is gone, so the launch screen stays until the new one has drawn
    showLaunchOverlay()
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
    // Scripts may open windows without a tap, for the web app's links after a request to Telegram. Frames of other
    // sites, such as bot web apps and embeds, still need a tapped link.
    let isTapped = navigationAction.navigationType == .linkActivated
    guard isTapped || Self.isAppMainFrame(navigationAction.sourceFrame as WKFrameInfo?) else {
      logger.info("Ignored a window that a frame opened without a tapped link")
      return nil
    }
    if Self.downloadSchemes.contains(scheme) {
      webView.startDownload(using: navigationAction.request) { [weak self] download in
        download.delegate = self
      }
    } else if !LocalServer.isAppURL(url) {
      openExternally(url, isTapped: isTapped)
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

  /// WebKit asks before every page gets the location, naming the page by its address, even after iOS granted the app
  /// the location. The app's own page skips that question; other sites, such as bot web apps, get the app's question
  /// with their host. WebKit calls this method of its private `WKUIDelegatePrivate` protocol when the delegate has
  /// it, and shows its own question otherwise.
  @objc(_webView:requestGeolocationAuthorizationForURL:frame:decisionHandler:)
  func webView(
    _ webView: WKWebView,
    requestGeolocationAuthorizationFor url: URL,
    frame: WKFrameInfo,
    decisionHandler: @escaping (Bool) -> Void
  ) {
    guard !Self.isAppMainFrame(frame) else {
      decisionHandler(true)
      return
    }
    guard let presenter = findModalPresenter() else {
      decisionHandler(false)
      return
    }
    let host = frame.securityOrigin.host.isEmpty ? url.host ?? url.absoluteString : frame.securityOrigin.host
    let alert = UIAlertController(
      title: String(format: Strings.locationRequest, host),
      message: nil,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: Strings.dontAllow, style: .cancel) { _ in
      decisionHandler(false)
    })
    alert.addAction(UIAlertAction(title: Strings.allow, style: .default) { _ in
      decisionHandler(true)
    })
    present(alert, from: presenter)
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
    present(alert, from: presenter)
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
    present(alert, from: presenter)
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
    present(alert, from: presenter)
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

extension WebViewController: UIScrollViewDelegate {
  /// A tap on the status bar scrolls the visible chat list to the top instead of the sentinel
  func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
    // A Safari view or a share sheet over the page gets the tap for itself
    if presentedViewController == nil {
      bridge.perform(.scrollToTop)
    }
    return false
  }
}

/// Hides the Previous/Next/Done bar above the keyboard. WebKit's content view, which becomes the first responder
/// when a field of the page is focused, asks the web view for its `inputAccessoryView`.
private final class AppWebView: WKWebView {
  override var inputAccessoryView: UIView? {
    nil
  }
}

/// The launch screen of `Info.plist`: the logo in the middle of the screen on the launch color. Like the launch screen,
/// it takes the touches meant for the page under it. While it is up, it is the one accessibility element instead of
/// the page, so VoiceOver and UI tests reach the page only once it shows.
private final class LaunchOverlayView: UIView {
  private static let accessibilityName = "Liquidgram"

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = WebViewController.backgroundColor
    accessibilityIdentifier = "liquidgram.launchOverlay"
    isAccessibilityElement = true
    accessibilityLabel = Self.accessibilityName

    let logoView = UIImageView(image: UIImage(named: "LaunchLogo"))
    logoView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(logoView)
    NSLayoutConstraint.activate([
      logoView.centerXAnchor.constraint(equalTo: centerXAnchor),
      logoView.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }
}

/// Keeps the page's own scroll view at its origin. The page is exactly as tall as the web view and scrolls elements
/// inside it, so any offset of the document, such as WebKit revealing a focused field, would move the whole app.
/// `WKScrollView` passes the delegate calls on to WebKit as well.
private final class DocumentScrollPin: NSObject, UIScrollViewDelegate {
  /// A zoomed page may move; the app's viewport does not allow zooming, though
  private static let zoomTolerance: CGFloat = 0.01

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    let origin = CGPoint(x: -scrollView.adjustedContentInset.left, y: -scrollView.adjustedContentInset.top)
    guard scrollView.contentOffset != origin,
          scrollView.zoomScale <= scrollView.minimumZoomScale + Self.zoomTolerance else {
      return
    }
    scrollView.contentOffset = origin
  }
}

/// Lets the page raise the keyboard for a field that a script focuses, for a moment after the app asked the page to
/// open a screen for typing, such as the chat search of a quick action. WebKit shows the keyboard for a focus only
/// while the user taps the page, unless the private input delegate of the web view (`_WKInputDelegate`) allows it
/// through `_webView:decidePolicyForFocusedElement:`. Without that delegate, the field is focused all the same, just
/// without the keyboard.
private final class ScriptFocusPolicy: NSObject {
  /// The values of `_WKFocusStartsInputSessionPolicy`
  private enum Policy: Int {
    case auto = 0
    case allow = 1
  }

  private static let inputDelegateSetter = NSSelectorFromString("_setInputDelegate:")

  private var keyboardDeadline: ContinuousClock.Instant?

  /// Becomes the input delegate of `webView`, which holds it weakly. Returns false when WebKit has no input delegate.
  func install(in webView: WKWebView) -> Bool {
    guard webView.responds(to: Self.inputDelegateSetter) else {
      return false
    }
    _ = webView.perform(Self.inputDelegateSetter, with: self)
    return true
  }

  /// The next field that a script focuses within `duration` gets the keyboard
  func allowKeyboard(for duration: Duration) {
    keyboardDeadline = ContinuousClock.now.advanced(by: duration)
  }

  @objc(_webView:decidePolicyForFocusedElement:)
  func decidePolicy(_ webView: WKWebView, forFocusedElement focusedElement: AnyObject) -> Int {
    guard let keyboardDeadline, ContinuousClock.now < keyboardDeadline else {
      return Policy.auto.rawValue
    }
    self.keyboardDeadline = nil
    return Policy.allow.rawValue
  }
}
