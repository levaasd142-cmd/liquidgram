import XCTest

/// Launch, query, wait and attachment helpers for the Liquidgram UI tests. Tests start the app from a clean state
/// unless they test persistence, wait generously because a cold start of the web app in a CI simulator takes 5 to 20
/// seconds, and attach named screenshots, which `run-ui-tests.sh` collects into the report. A failed wait also
/// attaches the accessibility tree, so the report shows what the test could see; trees are kept for failed tests only.
class LiquidgramUITestCase: XCTestCase {
  /// Long enough for a cold start of the web app in a CI simulator
  static let launchTimeout: TimeInterval = 60
  static let elementTimeout: TimeInterval = 20
  /// Native actions run once the web app reports that it is ready, after its cold start
  static let actionTimeout: TimeInterval = 40
  static let pollInterval: TimeInterval = 0.5
  /// A prompt for the notification permission shows right after the tap that triggers it
  static let notificationPromptTimeout: TimeInterval = 2

  static let userScriptEnvironmentKey = "LIQUIDGRAM_TEST_USER_SCRIPT"
  static let selfTestEnvironmentKey = "LIQUIDGRAM_TEST_SELFTEST_SCRIPT"
  /// `run-ui-tests.sh` sets `TEST_RUNNER_LIQUIDGRAM_APPEARANCE=dark` for the pass in dark mode, and `xcodebuild`
  /// passes it to the test runner without the prefix
  static let appearanceEnvironmentKey = "LIQUIDGRAM_APPEARANCE"

  static let webViewIdentifier = "liquidgram.webview"
  static let lockIdentifier = "liquidgram.lock"
  static let unlockButtonIdentifier = "liquidgram.lock.unlock"
  static let privacyShieldIdentifier = "liquidgram.privacyShield"
  static let startupErrorIdentifier = "liquidgram.startupError"
  static let selfTestResultIdentifier = "liquidgram.selftest.result"

  private static let fixtureExtension = "js"
  private static let scriptSeparator = "\n;\n"
  private static let springboardBundleIdentifier = "com.apple.springboard"
  private static let allowButtonLabel = "Allow"
  private static let keyboardIntroductionButtonLabel = "Continue"
  private static let pngType = "public.png"
  private static let jsonType = "public.json"
  private static let maxAttachmentNameLength = 48

  /// What a test launches the app with
  struct Launch {
    /// `-LiquidgramResetState YES`: no native settings and no web data from earlier tests
    var shouldResetState = true
    /// Seeds the demo account of `Fixtures/demo-account.js`, which shows chats without a connection to Telegram
    var shouldSeedDemoAccount = false
    /// Keeps a stored session offline with `Fixtures/offline-api.js`, as the demo account always is
    var shouldStayOffline = false
    /// Runs `Fixtures/selftest.js` once the page is ready and shows its report as `selfTestResultIdentifier`
    var shouldRunSelfTest = false
    /// Injects `Fixtures/ui-probe.js`, which reports the page's measurements and adds buttons that run page code
    var shouldInstallProbe = false
    var arguments: [String] = []
  }

  private var currentApp: XCUIApplication?

  /// The app of the last `launchApp` call
  @MainActor
  var app: XCUIApplication {
    if let currentApp {
      return currentApp
    }
    let app = XCUIApplication()
    currentApp = app
    return app
  }

  /// The page of the web app
  @MainActor
  var webView: XCUIElement {
    app.webViews.firstMatch
  }

  /// `-dark` in the pass that runs in dark mode, so the screenshots of both passes keep apart
  private static var appearanceSuffix: String {
    guard let appearance = ProcessInfo.processInfo.environment[appearanceEnvironmentKey], !appearance.isEmpty else {
      return ""
    }
    return "-\(appearance)"
  }

  override func setUpWithError() throws {
    try super.setUpWithError()
    // Each step needs the previous one, so the first failure ends the test
    continueAfterFailure = false
  }

  // MARK: - Launch

  @MainActor
  @discardableResult
  func launchApp(_ launch: Launch = Launch()) throws -> XCUIApplication {
    // A test that turned the simulator and failed before turning it back must not leave the next one in landscape
    if XCUIDevice.shared.orientation != .portrait {
      XCUIDevice.shared.orientation = .portrait
    }
    let app = XCUIApplication()
    // The assertions look for the English texts of the web app and the native screens
    var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    if launch.shouldResetState {
      arguments += ["-LiquidgramResetState", "YES"]
    }
    app.launchArguments = arguments + launch.arguments

    let errorRecorder = try loadFixture("page-errors")
    var userScripts = [errorRecorder]
    if launch.shouldSeedDemoAccount || launch.shouldStayOffline {
      userScripts.append(try loadFixture("offline-api"))
    }
    if launch.shouldSeedDemoAccount {
      userScripts.append(try loadFixture("demo-account"))
    }
    if launch.shouldInstallProbe {
      userScripts.append(try loadFixture("ui-probe"))
    }
    app.launchEnvironment[Self.userScriptEnvironmentKey] = Self.encodeScript(
      userScripts.joined(separator: Self.scriptSeparator)
    )
    if launch.shouldRunSelfTest {
      app.launchEnvironment[Self.selfTestEnvironmentKey] = Self.encodeScript(try loadFixture("selftest"))
    }

    currentApp = app
    app.launch()
    return app
  }

  func loadFixture(_ name: String) throws -> String {
    let bundle = Bundle(for: LiquidgramUITestCase.self)
    let url = try XCTUnwrap(
      bundle.url(forResource: name, withExtension: Self.fixtureExtension),
      "The test bundle lacks the fixture \(name).\(Self.fixtureExtension)"
    )
    return try String(contentsOf: url, encoding: .utf8)
  }

  private static func encodeScript(_ source: String) -> String {
    Data(source.utf8).base64EncodedString()
  }

  // MARK: - Queries

  static func makeLabelPredicate(containing text: String) -> NSPredicate {
    NSPredicate(format: "label CONTAINS %@", text)
  }

  /// A native element by its accessibility identifier, whatever its type
  @MainActor
  func findNativeElement(_ identifier: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// Elements of any type whose label contains `text`
  @MainActor
  func findElements(in root: XCUIElement, labelContaining text: String) -> XCUIElementQuery {
    root.descendants(matching: .any).matching(Self.makeLabelPredicate(containing: text))
  }

  /// The outermost element whose label contains `text`. Web content exposes a chat of the list as one button whose
  /// label holds the whole row, and a message as a static text.
  @MainActor
  func findElement(in root: XCUIElement, labelContaining text: String) -> XCUIElement {
    findElements(in: root, labelContaining: text).firstMatch
  }

  /// A static text whose label contains `text`
  @MainActor
  func findStaticText(in root: XCUIElement, containing text: String) -> XCUIElement {
    root.staticTexts.matching(Self.makeLabelPredicate(containing: text)).firstMatch
  }

  /// A text field or text view with this label or placeholder. The composer of the web app is a text view, the
  /// search fields and the API key fields are text fields.
  @MainActor
  func findTextInput(in root: XCUIElement, labeled label: String) -> XCUIElement {
    let types = [XCUIElement.ElementType.textField, .textView, .searchField].map { NSNumber(value: $0.rawValue) }
    let predicate = NSPredicate(
      format: "(label == %@ OR placeholderValue == %@) AND elementType IN %@",
      label,
      label,
      types as NSArray
    )
    return root.descendants(matching: .any).matching(predicate).firstMatch
  }

  /// The software keyboard
  @MainActor
  var keyboard: XCUIElement {
    app.keyboards.firstMatch
  }

  // MARK: - Waiting

  /// Waits until `element` exists; on timeout attaches the screen and the accessibility tree, then fails
  @MainActor
  @discardableResult
  func waitFor(
    _ element: XCUIElement,
    timeout: TimeInterval = LiquidgramUITestCase.elementTimeout,
    _ description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> XCUIElement {
    if !element.waitForExistence(timeout: timeout) {
      attachFailureContext(description)
      XCTFail("Not found within \(Int(timeout)) s: \(description)", file: file, line: line)
    }
    return element
  }

  /// Waits until an element of `query` can be tapped. Web content keeps screens that slid away, such as the chat
  /// list under an opened chat, in the accessibility tree, so existence alone does not tell what is on screen.
  @MainActor
  @discardableResult
  func waitForHittable(
    _ query: XCUIElementQuery,
    timeout: TimeInterval = LiquidgramUITestCase.elementTimeout,
    _ description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> XCUIElement {
    var match: XCUIElement?
    let isFound = waitUntil(timeout: timeout) {
      match = query.allElementsBoundByIndex.first { $0.isHittable }
      return match != nil
    }
    if !isFound {
      attachFailureContext(description)
      XCTFail("Not on screen within \(Int(timeout)) s: \(description)", file: file, line: line)
    }
    return match ?? query.firstMatch
  }

  /// Waits until `element` can be tapped, for elements that exist before the web app shows them
  @MainActor
  @discardableResult
  func waitForHittable(
    _ element: XCUIElement,
    timeout: TimeInterval = LiquidgramUITestCase.elementTimeout,
    _ description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> XCUIElement {
    if !waitUntil(timeout: timeout, { element.exists && element.isHittable }) {
      attachFailureContext(description)
      XCTFail("Not on screen within \(Int(timeout)) s: \(description)", file: file, line: line)
    }
    return element
  }

  /// Waits until the row of a chat in the chat list is on screen. The rows enter the accessibility tree a moment
  /// before the web app shows them, and a tap before that hits whatever still covers them.
  @MainActor
  @discardableResult
  func waitForChatRow(
    titled title: String,
    timeout: TimeInterval = LiquidgramUITestCase.launchTimeout,
    _ description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) -> XCUIElement {
    waitForHittable(
      findElements(in: webView, labelContaining: title),
      timeout: timeout,
      description,
      file: file,
      line: line
    )
  }

  /// Waits until `element` is gone; on timeout attaches the screen and the accessibility tree, then fails
  @MainActor
  func waitForDisappearance(
    of element: XCUIElement,
    timeout: TimeInterval = LiquidgramUITestCase.elementTimeout,
    _ description: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    if !waitUntil(timeout: timeout, { !element.exists }) {
      attachFailureContext(description)
      XCTFail("Still shown after \(Int(timeout)) s: \(description)", file: file, line: line)
    }
  }

  /// Polls `condition` until it holds or `timeout` passes
  @MainActor
  func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(Self.pollInterval))
    }
    return condition()
  }

  /// Lets the app run for `duration` without touching it
  @MainActor
  func pause(_ duration: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(duration))
  }

  /// Scrolls the page up until `element` can be tapped
  @MainActor
  func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 8) {
    var swipes = 0
    while !element.isHittable && swipes < maxSwipes {
      webView.swipeUp()
      swipes += 1
    }
  }

  // MARK: - System UI

  /// A connected session of the web app asks for the notification permission after its first tap, and iOS shows the
  /// prompt above the app until it is answered. The offline demo account does not get that far, but a prompt would
  /// block every later step, so tests answer it after their first tap. It appears once per simulator.
  @MainActor
  func allowNotificationsIfAsked(timeout: TimeInterval = LiquidgramUITestCase.notificationPromptTimeout) {
    let springboard = XCUIApplication(bundleIdentifier: Self.springboardBundleIdentifier)
    let allowButton = springboard.alerts.buttons[Self.allowButtonLabel]
    guard allowButton.waitForExistence(timeout: timeout) else {
      return
    }
    attachScreenshot("notification-permission-prompt")
    allowButton.tap()
  }

  /// The status bar, which SpringBoard draws over the app; an empty frame while it is hidden
  @MainActor
  var statusBarFrame: CGRect {
    let statusBar = XCUIApplication(bundleIdentifier: Self.springboardBundleIdentifier).statusBars.firstMatch
    return statusBar.exists ? statusBar.frame : .zero
  }

  /// A new simulator explains swipe typing the first time the letter keyboard opens
  @MainActor
  func dismissKeyboardIntroductionIfShown() {
    let continueButton = keyboard.buttons[Self.keyboardIntroductionButtonLabel]
    if continueButton.exists {
      attachScreenshot("keyboard-introduction")
      continueButton.tap()
    }
  }

  // MARK: - Attachments

  /// A screenshot of the whole screen, including system alerts and the keyboard, kept even when the test passes
  @MainActor
  func attachScreenshot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: Self.pngType)
    attachment.name = name + Self.appearanceSuffix
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// The accessibility tree of the app as XCUITest sees it, for writing and fixing queries. It is kept only when the
  /// test fails, since the trees of passing tests make the report large without telling anything.
  @MainActor
  func attachAccessibilityTree(_ name: String) {
    let attachment = XCTAttachment(string: app.debugDescription)
    attachment.name = "ax-" + name + Self.appearanceSuffix
    attachment.lifetime = .deleteOnSuccess
    add(attachment)
  }

  /// A JSON report, such as the self-test's, which `report.mjs` turns into a table
  func attachJSON(_ json: String, name: String) {
    let attachment = XCTAttachment(data: Data(json.utf8), uniformTypeIdentifier: Self.jsonType)
    attachment.name = name + Self.appearanceSuffix
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor
  private func attachFailureContext(_ description: String) {
    let name = "failure-" + Self.makeAttachmentName(description)
    attachScreenshot(name)
    attachAccessibilityTree(name)
  }

  /// The first lowercase ASCII words joined by dashes, which make readable file names in the report
  private static func makeAttachmentName(_ text: String) -> String {
    let characters = text.lowercased().unicodeScalars
      .map { $0.isASCII && CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
    var name = ""
    for word in String(characters).split(separator: " ") {
      let nextName = name.isEmpty ? String(word) : "\(name)-\(word)"
      guard nextName.count <= maxAttachmentNameLength else {
        break
      }
      name = nextName
    }
    return name
  }
}
