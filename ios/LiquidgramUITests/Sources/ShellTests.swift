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
  /// The keyboard's frame in the accessibility tree and the one that the app gets in its notifications may differ a
  /// little on newer systems, whose keyboard has rounded corners and margins
  private static let keyboardEdgeTolerance: CGFloat = 12
  /// The composer rests on the keyboard, below the web app's bottom margin
  private static let maxComposerGap: CGFloat = 60
  /// The resize follows the keyboard's animation, and the page lays itself out again after it
  private static let layoutTimeout: TimeInterval = 5
  private static let rotationDelay: TimeInterval = 2

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
    XCTAssertEqual(
      webView.frame.maxY,
      keyboardFrame.minY,
      accuracy: Self.keyboardEdgeTolerance,
      "The web view \(webView.frame) does not end at the keyboard \(keyboardFrame)"
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

  /// The title in the header of the demo chat; the chat list row has a longer label
  @MainActor
  private var chatHeaderTitle: XCUIElementQuery {
    webView.buttons.matching(NSPredicate(format: "label == %@", Self.demoChatTitle))
  }
}
