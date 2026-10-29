import XCTest

/// The native shell around the web app: the web view starts below the status bar, it ends at the top of the keyboard
/// instead of sliding the whole page up, it gets its full height back when the keyboard hides, and the iPhone app
/// stays in portrait.
final class ShellTests: LiquidgramUITestCase {
  private static let demoChatTitle = "Аня Смирнова"
  /// Messages of the demo chat in `Fixtures/demo-account.js`. A single tap on a message only takes the focus from the
  /// composer.
  private static let demoMessageTexts = ["Договорились", "Во сколько завтра", "Давай в 19:00", "Ахахах ладно"]
  private static let composerLabel = "Message"
  private static let menuButtonLabel = "Open menu"
  /// Frames of web content come from another process and may be off by rounding
  private static let frameTolerance: CGFloat = 1
  /// The keyboard in the accessibility tree starts at its keys, below the suggestions bar, which the keyboard frame of
  /// the app's notifications includes
  private static let maxKeyboardBarHeight: CGFloat = 60
  /// The composer rests on the keyboard: the suggestions bar and the web app's margins are between them
  private static let maxComposerGap: CGFloat = 100
  /// The resize follows the keyboard's animation, and the page lays itself out again after it
  private static let layoutTimeout: TimeInterval = 5
  private static let rotationDelay: TimeInterval = 2
  private static let lateWindowButtonLabel = "Open a page later"
  /// The page opens its window 1.5 seconds after the tap, and Safari's view controller slides in after that
  private static let inAppBrowserTimeout: TimeInterval = 15
  /// A button over the page that opens a web page 1.5 seconds after the tap, as the web app does for links that wait
  /// for an answer from Telegram first. WebKit's pop-up blocker drops such a window once the tap is a second old,
  /// unless the app lets scripts open windows.
  private static let lateWindowScript = """
    document.addEventListener('DOMContentLoaded', () => {
      const button = document.createElement('button');
      button.textContent = 'Open later';
      button.setAttribute('aria-label', '\(lateWindowButtonLabel)');
      button.style.cssText = 'position: fixed; z-index: 2147483647; left: 50%; top: 50%; padding: 24px;'
        + 'transform: translate(-50%, -50%); font-size: 20px';
      button.addEventListener('click', () => {
        setTimeout(() => window.open('https://example.org/', '_blank', 'noopener'), 1500);
      });
      document.body.appendChild(button);
    });
    """

  /// Typing in a chat leaves the header in place: the web view ends at the top of the keyboard, the composer rests on
  /// the keyboard, and everything is back where it was once the keyboard hides
  @MainActor
  func testKeyboardResizesPageAndRestoresIt() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    let chat = waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    let menuButton = waitFor(webView.buttons[Self.menuButtonLabel], "the menu button of the chat list")
    let statusBarBottom = statusBarFrame.maxY
    XCTAssertGreaterThanOrEqual(
      webView.frame.minY,
      statusBarBottom - Self.frameTolerance,
      "The web view \(webView.frame) starts under the status bar, which ends at y \(statusBarBottom)"
    )
    XCTAssertGreaterThanOrEqual(
      menuButton.frame.minY,
      webView.frame.minY,
      "The menu button \(menuButton.frame) is above the web view \(webView.frame)"
    )
    attachScreenshot("01-chat-list")

    chat.tap()
    allowNotificationsIfAsked()
    let composer = waitForHittable(findTextInput(in: webView, labeled: Self.composerLabel), "the composer")
    let title = waitForHittable(chatHeaderTitle, "the header of the opened chat")
    let webViewFrame = webView.frame
    let titleFrame = title.frame
    let composerFrame = composer.frame
    attachScreenshot("02-chat")

    composer.tap()
    let keyboard = waitFor(self.keyboard, "the software keyboard")
    dismissKeyboardIntroductionIfShown()
    _ = waitUntil(timeout: Self.layoutTimeout) {
      composer.frame.maxY <= keyboard.frame.minY + Self.frameTolerance
    }
    let keyboardFrame = keyboard.frame
    attachScreenshot("03-keyboard-up")
    XCTAssertTrue(title.isHittable, "The chat header cannot be tapped while the keyboard is up")
    XCTAssertEqual(
      title.frame.minY,
      titleFrame.minY,
      accuracy: Self.frameTolerance,
      "The chat header moved from \(titleFrame) to \(title.frame) when the keyboard came up"
    )
    let keyboardGap = keyboardFrame.minY - webView.frame.maxY
    XCTAssertTrue(
      keyboardGap >= -Self.frameTolerance && keyboardGap <= Self.maxKeyboardBarHeight,
      "The web view \(webView.frame) does not end at the top of the keyboard \(keyboardFrame)"
    )
    XCTAssertLessThanOrEqual(
      composer.frame.maxY,
      keyboardFrame.minY + Self.frameTolerance,
      "The composer \(composer.frame) is under the keyboard \(keyboardFrame)"
    )
    XCTAssertLessThanOrEqual(
      keyboardFrame.minY - composer.frame.maxY,
      Self.maxComposerGap,
      "The composer \(composer.frame) is far above the keyboard \(keyboardFrame)"
    )

    let messagePredicate = NSCompoundPredicate(
      orPredicateWithSubpredicates: Self.demoMessageTexts.map(Self.makeLabelPredicate(containing:))
    )
    waitForHittable(webView.staticTexts.matching(messagePredicate), "a message above the keyboard").tap()
    waitForDisappearance(of: keyboard, timeout: Self.layoutTimeout, "the keyboard after a tap on a message")
    _ = waitUntil(timeout: Self.layoutTimeout) {
      abs(composer.frame.minY - composerFrame.minY) <= Self.frameTolerance
    }
    attachScreenshot("04-keyboard-hidden")
    XCTAssertEqual(webView.frame, webViewFrame, "The web view did not get its frame back after the keyboard hid")
    XCTAssertEqual(
      title.frame.minY,
      titleFrame.minY,
      accuracy: Self.frameTolerance,
      "The chat header moved from \(titleFrame) to \(title.frame) after the keyboard hid"
    )
    XCTAssertEqual(
      composer.frame.minY,
      composerFrame.minY,
      accuracy: Self.frameTolerance,
      "The composer moved from \(composerFrame) to \(composer.frame) after the keyboard hid"
    )
  }

  /// Turning the iPhone sideways leaves the app in portrait, the layout that the web app has for phones
  @MainActor
  func testIPhoneStaysInPortrait() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    guard UIDevice.current.userInterfaceIdiom == .phone else {
      throw XCTSkip("iPad turns to every orientation")
    }

    XCUIDevice.shared.orientation = .landscapeLeft
    pause(Self.rotationDelay)
    let windowFrame = app.windows.firstMatch.frame
    attachScreenshot("01-turned-sideways")
    // Back before the assertion, which ends the test when it fails
    XCUIDevice.shared.orientation = .portrait
    XCTAssertLessThan(windowFrame.width, windowFrame.height, "The app turned to landscape: \(windowFrame)")
  }

  /// A window that the page opens well after the tap, as for the "Log in" buttons of bots, shows the web page in the
  /// in-app browser instead of being dropped
  @MainActor
  func testWindowOpenedLateShowsInAppBrowser() throws {
    try launchApp(pageScript: Self.lateWindowScript)
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    let button = waitForHittable(webView.buttons[Self.lateWindowButtonLabel], "the button of the test page")
    button.tap()
    let isCovered = waitUntil(timeout: Self.inAppBrowserTimeout) {
      !button.isHittable
    }
    attachScreenshot("01-in-app-browser")
    XCTAssertTrue(isCovered, "No in-app browser covers the page after it opened a window 1.5 seconds after the tap")
    XCTAssertEqual(app.state, .runningForeground, "The link left the app")
  }

  /// The title in the header of the demo chat; the chat list row has a longer label
  @MainActor
  private var chatHeaderTitle: XCUIElementQuery {
    webView.buttons.matching(NSPredicate(format: "label == %@", Self.demoChatTitle))
  }

  /// Launches the app like `launchApp(_:)` with the demo account, plus one more page script after the fixtures
  @MainActor
  private func launchApp(pageScript: String) throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-LiquidgramResetState", "YES"]
    let scripts = try ["page-errors", "offline-api", "demo-account"].map { try loadFixture($0) } + [pageScript]
    app.launchEnvironment[Self.userScriptEnvironmentKey] = Data(scripts.joined(separator: "\n;\n").utf8)
      .base64EncodedString()
    app.launch()
  }
}
