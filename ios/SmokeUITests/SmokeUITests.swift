import XCTest

/// Scratch UI tests of the ios-v2/swift agent, run against the bridge smoke page of `ios-smoke/smoke.sh`: the status
/// bar tap, the keyboard without the form toolbar and after `openSearch`, the lock with a slow fake Face ID,
/// `liquidgram:` and `tg:` links and a home-screen quick action. They live only on the scratch branch.
final class SmokeUITests: XCTestCase {
  private static let springboardBundleIdentifier = "com.apple.springboard"
  private static let userScriptEnvironmentKey = "LIQUIDGRAM_TEST_USER_SCRIPT"
  private static let launchTimeout: TimeInterval = 40
  private static let actionTimeout: TimeInterval = 10
  /// Longer than the 6 seconds of the slow fake Face ID
  private static let unlockTimeout: TimeInterval = 20
  /// How long a keyboard that should stay hidden gets to appear
  private static let keyboardAbsenceTimeout: TimeInterval = 4
  private static let promptTimeout: TimeInterval = 4
  private static let backgroundDuration: UInt32 = 2
  private static let iconPressDuration: TimeInterval = 1.2
  private static let maxHomeScreenSwipes = 4
  private static let formToolbarButtonLabels = ["Done", "Previous", "Next"]
  /// The time in the status bar, left of the Dynamic Island
  private static let statusBarTapOffset = CGVector(dx: 50, dy: 22)

  @MainActor
  func testFocusWithoutActionKeepsKeyboardHidden() {
    let app = launchApp(userScript: "window.__smokeFocusOnLoad = true;")
    let isFocused = findText("field focused", in: app).waitForExistence(timeout: Self.actionTimeout)
    XCTAssertTrue(isFocused, "the page focused its field")
    let hasKeyboard = app.keyboards.firstMatch.waitForExistence(timeout: Self.keyboardAbsenceTimeout)
    takeScreenshot("f-focus-without-action")
    XCTAssertFalse(hasKeyboard, "a focus without a native action brings up no keyboard")
  }

  @MainActor
  func testKeyboardHasNoFormToolbar() {
    let app = launchApp()
    let field = app.textFields.matching(NSPredicate(format: "label == %@", "Smoke field")).firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: Self.actionTimeout), "the text field of the smoke page")
    field.tap()
    let keyboard = app.keyboards.firstMatch
    let hasKeyboard = keyboard.waitForExistence(timeout: Self.actionTimeout)
    takeScreenshot("k-keyboard")
    XCTAssertTrue(hasKeyboard, "the software keyboard")
    let keyboardFrame = keyboard.frame
    let toolbarButtons = app.buttons
      .matching(NSPredicate(format: "label IN %@", Self.formToolbarButtonLabels as NSArray))
      .allElementsBoundByIndex
      .filter { !keyboardFrame.contains($0.frame) }
    XCTAssertTrue(
      toolbarButtons.isEmpty,
      "form toolbar buttons: " + toolbarButtons.map { "\($0.label) \($0.frame)" }.joined(separator: ", ")
    )
  }

  @MainActor
  func testLinksBecomeOpenLinkActions() throws {
    let app = launchApp()
    let links = [
      ("liquidgram://resolve?domain=durov", "action openLink tg://resolve?domain=durov"),
      ("tg://resolve?domain=telegram", "action openLink tg://resolve?domain=telegram"),
      ("liquidgram://open?url=https%3A%2F%2Ft.me%2Fdurov", "action openLink https://t.me/durov"),
    ]
    for (index, link) in links.enumerated() {
      app.open(try XCTUnwrap(URL(string: link.0)))
      acceptOpenPrompt(screenshotName: "l-prompt-\(index)")
      let isDelivered = findText(link.1, in: app).waitForExistence(timeout: Self.actionTimeout)
      takeScreenshot("l-link-\(index)")
      XCTAssertTrue(isDelivered, "\(link.0) reaches the page as \(link.1)")
    }
  }

  @MainActor
  func testLockWaitsForSlowAuthenticationAndLocksAgain() {
    let app = launchApp(
      arguments: [
        "-appLockEnabled", "YES",
        "-appLockDelay", "0",
        "-LiquidgramFakeAuthentication", "success",
        "-LiquidgramFakeAuthenticationDelay", "6",
      ],
      waitsForPage: false
    )
    let lock = app.descendants(matching: .any).matching(identifier: "liquidgram.lock").firstMatch
    XCTAssertTrue(lock.waitForExistence(timeout: Self.actionTimeout), "the lock screen at launch")
    takeScreenshot("a-locked-at-launch")
    XCTAssertTrue(waitForDisappearance(of: lock, timeout: Self.unlockTimeout), "the lock opens after Face ID")
    takeScreenshot("a-unlocked")

    XCUIDevice.shared.press(.home)
    sleep(Self.backgroundDuration)
    app.activate()
    XCTAssertTrue(lock.waitForExistence(timeout: Self.actionTimeout), "the lock after the background")
    takeScreenshot("a-locked-again")
    XCTAssertTrue(waitForDisappearance(of: lock, timeout: Self.unlockTimeout), "the lock opens again")
  }

  @MainActor
  func testQuickActionFromHomeScreen() {
    let app = launchApp()
    XCUIDevice.shared.press(.home)
    let springboard = XCUIApplication(bundleIdentifier: Self.springboardBundleIdentifier)
    let icon = springboard.icons["Liquidgram"]
    XCTAssertTrue(icon.waitForExistence(timeout: Self.actionTimeout), "the app icon")
    var swipes = 0
    while !icon.isHittable && swipes < Self.maxHomeScreenSwipes {
      springboard.swipeLeft()
      swipes += 1
    }
    icon.press(forDuration: Self.iconPressDuration)
    let item = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "New Message"))
      .firstMatch
    let hasMenu = item.waitForExistence(timeout: Self.actionTimeout)
    takeScreenshot("q-quick-actions")
    XCTAssertTrue(hasMenu, "the New Message quick action in the menu of the icon")
    guard hasMenu else {
      return
    }
    item.tap()
    let isDelivered = findText("action newMessage", in: app).waitForExistence(timeout: Self.actionTimeout)
    takeScreenshot("q-new-message")
    XCTAssertTrue(isDelivered, "the quick action reaches the page as newMessage")
  }

  @MainActor
  func testSearchActionBringsUpKeyboard() {
    let app = launchApp(arguments: ["-LiquidgramTestAction", "openSearch"])
    XCTAssertTrue(
      findText("action openSearch", in: app).waitForExistence(timeout: Self.actionTimeout),
      "the openSearch action reaches the page"
    )
    let isFocused = findText("field focused", in: app).waitForExistence(timeout: Self.actionTimeout)
    XCTAssertTrue(isFocused, "the page focused its field")
    let hasKeyboard = app.keyboards.firstMatch.waitForExistence(timeout: Self.actionTimeout)
    takeScreenshot("f-search-keyboard")
    XCTAssertTrue(hasKeyboard, "the keyboard comes up for the field that openSearch focused")
  }

  @MainActor
  func testStatusBarTapScrollsToTop() {
    let app = launchApp()
    app.coordinate(withNormalizedOffset: .zero).withOffset(Self.statusBarTapOffset).tap()
    let isDelivered = findText("action scrollToTop", in: app).waitForExistence(timeout: Self.actionTimeout)
    takeScreenshot("s-status-bar-tap")
    XCTAssertTrue(isDelivered, "a status bar tap reaches the page as scrollToTop")
  }

  @MainActor
  private func launchApp(
    arguments: [String] = [],
    userScript: String? = nil,
    waitsForPage: Bool = true
  ) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-LiquidgramResetState", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
      + arguments
    if let userScript {
      app.launchEnvironment[Self.userScriptEnvironmentKey] = Data(userScript.utf8).base64EncodedString()
    }
    app.launch()
    if waitsForPage {
      let isReady = findText("ready", in: app).waitForExistence(timeout: Self.launchTimeout)
      XCTAssertTrue(isReady, "the smoke page answered its settings request")
    }
    return app
  }

  @MainActor
  private func findText(_ text: String, in app: XCUIApplication) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
  }

  @MainActor
  private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
    let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
  }

  /// iOS may ask before it opens a link of another app
  @MainActor
  private func acceptOpenPrompt(screenshotName: String) {
    let springboard = XCUIApplication(bundleIdentifier: Self.springboardBundleIdentifier)
    let openButton = springboard.buttons["Open"]
    if openButton.waitForExistence(timeout: Self.promptTimeout) {
      takeScreenshot(screenshotName)
      openButton.tap()
    }
  }

  @MainActor
  private func takeScreenshot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    if let directory = ProcessInfo.processInfo.environment["SMOKE_SHOTS"] {
      let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
      try? screenshot.pngRepresentation.write(to: url)
    }
  }
}
