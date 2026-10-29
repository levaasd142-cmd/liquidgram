import XCTest

/// What the iPhone app does since its first version: start the bundled web app, give it the browser features it
/// needs, keep the focused field above the keyboard, show a signed-in session and keep it across restarts.
/// `run-ui-tests.sh` runs `testDemoAccount` a second time with the simulator in dark mode.
final class CoreTests: LiquidgramUITestCase {
  private static let apiIdLabel = "API ID"
  private static let apiHashLabel = "API hash"
  /// Part of the description on the API keys screen
  private static let apiKeysDescription = "needs your own API keys"
  /// The page that `compatTest.js` shows in browsers that lack a feature the web app needs
  private static let unsupportedBrowserText = "not supported"
  private static let typedApiId = "2040"
  private static let composerLabel = "Message"
  private static let typedMessage = "Typed by the UI test"
  /// A private chat, a group and a message of the private chat in `Fixtures/demo-account.js`
  private static let demoChatTitle = "Аня Смирнова"
  private static let demoGroupTitle = "Бразы"
  private static let demoMessage = "Во сколько завтра встречаемся?"
  private static let selfTestTimeout: TimeInterval = 90
  /// The web app writes its cache to IndexedDB at most every 5 seconds, and at once when the page loses focus
  private static let cacheWriteDelay: TimeInterval = 6
  private static let backgroundDelay: TimeInterval = 2
  /// Frames of web content and of the keyboard come from different processes and may differ by rounding
  private static let frameTolerance: CGFloat = 1

  /// A clean install shows the API keys screen, the first screen of a build without API keys of its own
  @MainActor
  func testColdStartShowsApiKeysScreen() throws {
    try launchApp()
    waitFor(webView, timeout: Self.launchTimeout, "the web view")
    waitFor(
      findTextInput(in: webView, labeled: Self.apiIdLabel),
      timeout: Self.launchTimeout,
      "the API ID field of the API keys screen"
    )
    waitFor(findTextInput(in: webView, labeled: Self.apiHashLabel), "the API hash field")
    waitFor(
      findElement(in: webView, labelContaining: Self.apiKeysDescription),
      "the description of the API keys screen"
    )
    attachScreenshot("01-api-keys-screen")
    attachAccessibilityTree("api-keys-screen")

    XCTAssertTrue(
      findNativeElement(Self.webViewIdentifier).exists,
      "No element has the identifier \(Self.webViewIdentifier)"
    )
    XCTAssertFalse(
      findElement(in: webView, labelContaining: Self.unsupportedBrowserText).exists,
      "The web app says that the browser is not supported"
    )
    XCTAssertFalse(findNativeElement(Self.startupErrorIdentifier).exists, "The app shows its startup error")
  }

  /// `Fixtures/selftest.js` checks the bridge, storage, crypto, workers, the local server and the user agent from
  /// inside the page
  @MainActor
  func testWebAppSelfTest() throws {
    try launchApp(Launch(shouldRunSelfTest: true))
    let result = waitFor(
      findNativeElement(Self.selfTestResultIdentifier),
      timeout: Self.selfTestTimeout,
      "the self-test result"
    )
    attachScreenshot("01-self-test-finished")

    let report = try XCTUnwrap(result.value as? String, "The self-test result has no report")
    attachJSON(report, name: "selftest-report")
    let decodedReport = try JSONDecoder().decode(SelfTestReport.self, from: Data(report.utf8))
    if let error = decodedReport.error {
      XCTFail("The self-test script failed: \(error)")
    }
    let checks = decodedReport.checks ?? []
    XCTAssertFalse(checks.isEmpty, "The self-test report has no checks")
    let failedChecks = checks.filter { !$0.ok }
    XCTAssertTrue(
      failedChecks.isEmpty,
      "Failed self-test checks: " + failedChecks.map { "\($0.name) (\($0.detail ?? ""))" }.joined(separator: "; ")
    )
  }

  /// The focused field of the web app stays above the keyboard
  @MainActor
  func testKeyboardKeepsFocusedFieldVisible() throws {
    try launchApp()
    let apiIdField = waitFor(
      findTextInput(in: webView, labeled: Self.apiIdLabel),
      timeout: Self.launchTimeout,
      "the API ID field"
    )
    apiIdField.tap()
    let keyboard = waitFor(self.keyboard, "the software keyboard")
    app.typeText(Self.typedApiId)
    let isTyped = waitUntil(timeout: Self.elementTimeout) {
      (apiIdField.value as? String)?.contains(Self.typedApiId) == true
    }
    attachScreenshot("01-keyboard-up")
    attachAccessibilityTree("keyboard-up")

    XCTAssertTrue(isTyped, "The API ID field shows \(String(describing: apiIdField.value)) instead of the typed digits")
    XCTAssertGreaterThan(keyboard.frame.height, 0, "The keyboard has no height")
    XCTAssertLessThanOrEqual(
      apiIdField.frame.maxY,
      keyboard.frame.minY + Self.frameTolerance,
      "The focused field \(apiIdField.frame) is under the keyboard \(keyboard.frame)"
    )
  }

  /// A signed-in session shows its chats, opens a chat and keeps the composer above the keyboard
  @MainActor
  func testDemoAccount() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    let chat = waitFor(
      findElement(in: webView, labelContaining: Self.demoChatTitle),
      timeout: Self.launchTimeout,
      "the chat list of the demo account"
    )
    waitFor(findElement(in: webView, labelContaining: Self.demoGroupTitle), "the group chat of the demo account")
    attachScreenshot("01-chat-list")
    attachAccessibilityTree("chat-list")

    chat.tap()
    allowNotificationsIfAsked()
    waitFor(findStaticText(in: webView, containing: Self.demoMessage), "a message of the opened chat")
    let composer = waitFor(findTextInput(in: webView, labeled: Self.composerLabel), "the composer")
    attachScreenshot("02-chat")

    composer.tap()
    let keyboard = waitFor(self.keyboard, "the software keyboard")
    dismissKeyboardIntroductionIfShown()
    app.typeText(Self.typedMessage)
    let isTyped = waitUntil(timeout: Self.elementTimeout) {
      (composer.value as? String)?.contains(Self.typedMessage) == true
    }
    attachScreenshot("03-composer-with-keyboard")
    attachAccessibilityTree("composer-with-keyboard")

    XCTAssertTrue(isTyped, "The composer shows \(String(describing: composer.value)) instead of the typed text")
    XCTAssertLessThanOrEqual(
      composer.frame.maxY,
      keyboard.frame.minY + Self.frameTolerance,
      "The composer \(composer.frame) is under the keyboard \(keyboard.frame)"
    )
  }

  /// The session and its cached chats survive a restart of the app: the website data store keeps them on disk, and the
  /// local server gives the page the same origin every time
  @MainActor
  func testDemoAccountSurvivesRestart() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitFor(
      findElement(in: webView, labelContaining: Self.demoChatTitle),
      timeout: Self.launchTimeout,
      "the chat list of the demo account"
    )
    pause(Self.cacheWriteDelay)
    XCUIDevice.shared.press(.home)
    pause(Self.backgroundDelay)
    app.terminate()

    try launchApp(Launch(shouldResetState: false, shouldStayOffline: true))
    waitFor(
      findElement(in: webView, labelContaining: Self.demoChatTitle),
      timeout: Self.launchTimeout,
      "the chat list after the restart"
    )
    attachScreenshot("01-chat-list-after-restart")
  }
}

/// The JSON that `Fixtures/selftest.js` returns, or the error report of `TestHooks` when the script throws
private struct SelfTestReport: Decodable {
  struct Check: Decodable {
    let name: String
    let ok: Bool
    let detail: String?
  }

  let checks: [Check]?
  let error: String?
}
