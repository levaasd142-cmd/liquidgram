import XCTest

/// The native features of version 2: app lock, privacy shield, quick actions, deep links, the iPhone section of the
/// Liquidgram settings and the keyboard without the form toolbar. They follow the shared contract of the v2 branches,
/// so they fail on a build without these features. The layout tests check bugs of the v1 app: headers under the
/// status bar and a chat header that scrolls away while typing.
final class FeatureTests: LiquidgramUITestCase {
  /// The faked Face ID takes this long, so the test sees the lock screen before it opens
  private static let slowAuthenticationDelay = "6"
  private static let failedAuthenticationDelay = "1"
  /// Longer than a faked failure, so the lock had its chance to open
  private static let afterFailureDelay: TimeInterval = 3
  private static let lockTimeout: TimeInterval = 10
  /// The faked authentication takes `slowAuthenticationDelay` seconds after the lock appears
  private static let unlockTimeout: TimeInterval = 20
  private static let backgroundDelay: TimeInterval = 2
  private static let shieldTimeout: TimeInterval = 10
  private static let demoChatTitle = "Аня Смирнова"
  private static let savedMessagesTitle = "Saved Messages"
  /// The only message of Saved Messages in `Fixtures/demo-account.js`
  private static let savedMessagesText = "Идеи для Liquidgram"
  private static let composerLabel = "Message"
  private static let searchLabel = "Search"
  private static let contactsSearchLabel = "Search contacts"
  private static let ghostModeToastPrefix = "Ghost mode is "
  private static let settingsTabLabel = "Settings"
  /// The settings row of the Liquidgram screen shows this description
  private static let liquidgramSettingsDescription = "Liquid Glass, ghost mode"
  private static let privacySettingsTitle = "Privacy and Security"
  /// Only the Liquidgram settings say this; the chat list has a ghost mode button as well
  private static let ghostModeSettingDescription = "Read, watch and stay invisible"
  private static let iPhoneSectionText = "iPhone"
  private static let settingsDeepLink = "liquidgram://settings"
  private static let openURLButtonLabel = "Open"
  private static let apiIdLabel = "API ID"
  private static let formToolbarButtonLabels = ["Done", "Previous", "Next"]
  private static let menuButtonLabel = "Open menu"
  private static let typedMessage = "Typed by the UI test"
  /// Frames of web content come from another process and may be off by rounding
  private static let frameTolerance: CGFloat = 1
  /// Notification Center opens with a drag from the top left corner of the screen
  private static let notificationCenterDragStart = CGVector(dx: 0.2, dy: 0.001)
  private static let notificationCenterDragEnd = CGVector(dx: 0.2, dy: 0.6)
  private static let homeIndicatorDragStart = CGVector(dx: 0.5, dy: 0.999)
  private static let homeIndicatorDragEnd = CGVector(dx: 0.5, dy: 0.4)
  /// A slow drag up from the home indicator that stops halfway opens the app switcher
  private static let appSwitcherDragEnd = CGVector(dx: 0.5, dy: 0.6)
  private static let appSwitcherHoldDuration: TimeInterval = 1
  private static let dragPressDuration: TimeInterval = 0.1

  // MARK: - App lock

  /// With Face ID faked to succeed, the lock shows at launch, opens, and closes again after the app was in the
  /// background with the delay set to immediately
  @MainActor
  func testAppLockOpensAndLocksAgainAfterBackground() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, arguments: [
      "-appLockEnabled", "YES",
      "-appLockDelay", "0",
      "-LiquidgramFakeAuthentication", "success",
      "-LiquidgramFakeAuthenticationDelay", Self.slowAuthenticationDelay,
    ]))
    let lock = waitFor(
      findNativeElement(Self.lockIdentifier),
      timeout: Self.lockTimeout,
      "the lock screen at launch, while the faked Face ID waits TestHooks.fakeAuthenticationDelay"
    )
    attachScreenshot("01-locked-at-launch")
    let unlockButton = waitFor(findNativeElement(Self.unlockButtonIdentifier), "the unlock button")
    XCTAssertTrue(unlockButton.isHittable, "The unlock button cannot be tapped")
    unlockButton.tap()
    waitForDisappearance(of: lock, timeout: Self.unlockTimeout, "the lock screen after Face ID succeeded")
    waitForChatRow(titled: Self.demoChatTitle, "the chats after unlocking")
    attachScreenshot("02-unlocked")

    XCUIDevice.shared.press(.home)
    pause(Self.backgroundDelay)
    app.activate()
    waitFor(lock, timeout: Self.lockTimeout, "the lock screen after the app returned from the background")
    attachScreenshot("03-locked-after-background")
    waitForDisappearance(of: lock, timeout: Self.unlockTimeout, "the lock screen after the second Face ID")
    attachScreenshot("04-unlocked-again")
  }

  /// With Face ID faked to fail, the app stays locked, also after a tap on the unlock button
  @MainActor
  func testAppLockStaysLockedWhenAuthenticationFails() throws {
    try launchApp(Launch(arguments: [
      "-appLockEnabled", "YES",
      "-LiquidgramFakeAuthentication", "failure",
      "-LiquidgramFakeAuthenticationDelay", Self.failedAuthenticationDelay,
    ]))
    let lock = waitFor(findNativeElement(Self.lockIdentifier), timeout: Self.lockTimeout, "the lock screen at launch")
    pause(Self.afterFailureDelay)
    attachScreenshot("01-failed-authentication")
    XCTAssertTrue(lock.exists, "The lock opened although Face ID failed")

    waitFor(findNativeElement(Self.unlockButtonIdentifier), "the unlock button").tap()
    pause(Self.afterFailureDelay)
    attachScreenshot("02-failed-again")
    XCTAssertTrue(lock.exists, "The lock opened although Face ID failed again")
    XCTAssertFalse(webView.isHittable, "The web app can be touched through the lock screen")
  }

  // MARK: - Privacy shield

  /// The shield covers the chats while the app is inactive, for example under Notification Center, and goes away
  /// when the app is active again
  @MainActor
  func testPrivacyShieldCoversAppWhileInactive() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")

    app.coordinate(withNormalizedOffset: Self.notificationCenterDragStart).press(
      forDuration: Self.dragPressDuration,
      thenDragTo: app.coordinate(withNormalizedOffset: Self.notificationCenterDragEnd)
    )
    let shield = waitFor(
      findNativeElement(Self.privacyShieldIdentifier),
      timeout: Self.shieldTimeout,
      "the privacy shield while Notification Center is open"
    )
    attachScreenshot("01-shield-under-notification-center")

    app.coordinate(withNormalizedOffset: Self.homeIndicatorDragStart).press(
      forDuration: Self.dragPressDuration,
      thenDragTo: app.coordinate(withNormalizedOffset: Self.homeIndicatorDragEnd)
    )
    app.activate()
    waitForDisappearance(of: shield, timeout: Self.shieldTimeout, "the privacy shield after the app became active")
    attachScreenshot("02-shield-removed")

    // For the report only: the app switcher shows the snapshot that iOS took as the app left the screen, which the
    // shield covers. The gesture is not reliable enough for an assertion.
    app.coordinate(withNormalizedOffset: Self.homeIndicatorDragStart).press(
      forDuration: Self.dragPressDuration,
      thenDragTo: app.coordinate(withNormalizedOffset: Self.appSwitcherDragEnd),
      withVelocity: .slow,
      thenHoldForDuration: Self.appSwitcherHoldDuration
    )
    attachScreenshot("03-app-switcher")
    app.activate()
  }

  // MARK: - Quick actions

  /// The Saved Messages quick action opens the chat with yourself
  @MainActor
  func testQuickActionOpensSavedMessages() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, arguments: ["-LiquidgramTestAction", "openSavedMessages"]))
    waitFor(findTextInput(in: webView, labeled: Self.composerLabel), timeout: Self.actionTimeout, "an opened chat")
    // The chat list under the opened chat has the same texts, but off screen
    waitForHittable(
      webView.staticTexts.matching(Self.makeLabelPredicate(containing: Self.savedMessagesText)),
      "the message of Saved Messages on screen"
    )
    waitForHittable(
      findElements(in: webView, labelContaining: Self.savedMessagesTitle),
      "the Saved Messages title on screen"
    )
    attachScreenshot("01-saved-messages")
  }

  /// The Search quick action focuses the chat search, so the keyboard comes up
  @MainActor
  func testQuickActionFocusesSearch() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, arguments: ["-LiquidgramTestAction", "openSearch"]))
    waitFor(keyboard, timeout: Self.actionTimeout, "the keyboard of the focused search")
    waitFor(findTextInput(in: webView, labeled: Self.searchLabel), "the search field")
    attachScreenshot("01-search-focused")
  }

  /// The New Message quick action opens the contacts to start a private chat with
  @MainActor
  func testQuickActionOpensNewMessage() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, arguments: ["-LiquidgramTestAction", "newMessage"]))
    waitFor(
      findTextInput(in: webView, labeled: Self.contactsSearchLabel),
      timeout: Self.actionTimeout,
      "the contacts picker"
    )
    attachScreenshot("01-new-message")
  }

  /// The Ghost Mode quick action switches ghost mode and says so in a toast
  @MainActor
  func testQuickActionTogglesGhostMode() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, arguments: ["-LiquidgramTestAction", "toggleGhostMode"]))
    waitFor(
      findElement(in: webView, labelContaining: Self.ghostModeToastPrefix),
      timeout: Self.actionTimeout,
      "the ghost mode toast"
    )
    attachScreenshot("01-ghost-mode-toast")
  }

  // MARK: - Deep links

  /// `liquidgram://settings` becomes `tg://settings`, which opens the settings of the web app
  @MainActor
  func testDeepLinkOpensSettings() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")

    app.open(try XCTUnwrap(URL(string: Self.settingsDeepLink)))
    acceptOpenURLPromptIfShown()
    waitFor(
      findElement(in: webView, labelContaining: Self.privacySettingsTitle),
      timeout: Self.actionTimeout,
      "the settings opened by \(Self.settingsDeepLink)"
    )
    attachScreenshot("01-settings-from-deep-link")
  }

  // MARK: - Settings

  /// Settings › Liquidgram has a section for the iPhone app
  @MainActor
  func testLiquidgramSettingsShowIPhoneSection() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    let settingsTab = waitForHittable(
      webView.buttons[Self.settingsTabLabel],
      timeout: Self.launchTimeout,
      "the Settings tab"
    )
    settingsTab.tap()
    allowNotificationsIfAsked()
    waitForHittable(
      findElements(in: webView, labelContaining: Self.liquidgramSettingsDescription),
      "the Liquidgram settings row"
    ).tap()
    waitFor(findElement(in: webView, labelContaining: Self.ghostModeSettingDescription), "the Liquidgram settings")
    attachScreenshot("01-liquidgram-settings")

    let section = waitFor(
      webView.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS[c] %@", Self.iPhoneSectionText)
      ).firstMatch,
      "the iPhone section of the Liquidgram settings"
    )
    scrollToElement(section)
    attachScreenshot("02-iphone-section")
    attachAccessibilityTree("iphone-section")
  }

  // MARK: - Layout

  /// The page extends under the status bar (`viewport-fit=cover`), so the web app keeps its headers below it
  @MainActor
  func testHeadersStayBelowStatusBar() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    let chat = waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    let menuButton = waitFor(webView.buttons[Self.menuButtonLabel], "the menu button of the chat list")
    let statusBarBottom = statusBarFrame.maxY
    attachScreenshot("01-chat-list-header")
    var problems: [String] = []
    if menuButton.frame.minY < statusBarBottom - Self.frameTolerance {
      problems.append("the chat list header starts at y \(menuButton.frame.minY)")
    }

    chat.tap()
    let chatTitle = waitForHittable(chatHeaderTitle, "the header of the opened chat")
    attachScreenshot("02-chat-header")
    if chatTitle.frame.minY < statusBarBottom - Self.frameTolerance {
      problems.append("the chat header starts at y \(chatTitle.frame.minY)")
    }
    XCTAssertTrue(
      problems.isEmpty,
      "Under the status bar, which ends at y \(statusBarBottom): " + problems.joined(separator: "; ")
    )
  }

  /// The opened chat keeps its header on screen while the keyboard is up, rather than the whole page scrolling up
  @MainActor
  func testChatHeaderStaysVisibleWhileTyping() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list").tap()
    allowNotificationsIfAsked()
    waitForHittable(findTextInput(in: webView, labeled: Self.composerLabel), "the composer").tap()
    waitFor(keyboard, "the software keyboard")
    dismissKeyboardIntroductionIfShown()
    app.typeText(Self.typedMessage)
    let statusBarBottom = statusBarFrame.maxY
    let title = chatHeaderTitle.firstMatch
    attachScreenshot("01-typing")
    XCTAssertTrue(
      title.exists && title.isHittable && title.frame.minY >= statusBarBottom - Self.frameTolerance,
      "The chat header \(title.frame) left the screen while typing; the status bar ends at y \(statusBarBottom)"
    )
  }

  /// The title in the header of the demo chat; the chat list row has a longer label
  @MainActor
  private var chatHeaderTitle: XCUIElementQuery {
    webView.buttons.matching(NSPredicate(format: "label == %@", Self.demoChatTitle))
  }

  // MARK: - Keyboard

  /// Web forms show the keyboard without WebKit's toolbar with the previous, next and done buttons
  @MainActor
  func testKeyboardHasNoFormToolbar() throws {
    try launchApp()
    waitForHittable(
      findTextInput(in: webView, labeled: Self.apiIdLabel),
      timeout: Self.launchTimeout,
      "the API ID field"
    ).tap()
    let keyboard = waitFor(self.keyboard, "the software keyboard")
    attachScreenshot("01-keyboard")

    let toolbarButtons = app.buttons.matching(
      NSPredicate(format: "label IN %@", Self.formToolbarButtonLabels as NSArray)
    ).allElementsBoundByIndex.filter { !keyboard.frame.contains($0.frame) }
    if !toolbarButtons.isEmpty {
      attachAccessibilityTree("keyboard-with-toolbar")
    }
    XCTAssertTrue(
      toolbarButtons.isEmpty,
      "The keyboard has the form toolbar: " + toolbarButtons.map(\.label).joined(separator: ", ")
    )
  }

  /// iOS may ask before an app opens a URL of another app
  @MainActor
  private func acceptOpenURLPromptIfShown() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let openButton = springboard.buttons[Self.openURLButtonLabel]
    if openButton.waitForExistence(timeout: Self.backgroundDelay) {
      attachScreenshot("open-url-prompt")
      openButton.tap()
    }
  }
}
