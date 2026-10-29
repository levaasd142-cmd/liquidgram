import UIKit
import XCTest

/// What the first user of the iPhone app reported: headers under the status bar whose buttons did not react, the whole
/// app sliding up with the keyboard, a keyboard that stayed while the messages were dragged, a landscape layout on a
/// turned iPhone, panels under the home indicator and links that never opened. The tests check the media viewer and
/// the message menu as well, since they have buttons in the same places. Each test checks everything it can before it
/// fails and names every problem it found, so one run of a broken build shows all of them.
///
/// Measurements inside the page and actions that XCUITest cannot perform come from `Fixtures/ui-probe.js`, which the
/// tests that need it inject with `Launch(fixtures: ["ui-probe"])`.
final class UsabilityTests: LiquidgramUITestCase {
  /// A private chat with a long history and the chat with a photo in `Fixtures/demo-account.js`
  private static let demoChatTitle = "Аня Смирнова"
  private static let photoChatTitle = "Катя Дизайн"
  private static let photoCaption = "Превью главного экрана"
  /// The newest message of the chat with Аня, right above the composer
  private static let newestMessage = "Договорились! До завтра"
  /// A message in the middle of the screen of that chat
  private static let middleMessage = "Во сколько завтра встречаемся?"
  private static let composerLabel = "Message"
  private static let typedText = "Typed by the UI test"

  // Labels of the web app's controls
  private static let menuButtonLabel = "Open menu"
  private static let searchLabel = "Search"
  private static let returnToChatListLabel = "Return to chat list"
  private static let ghostModeLabel = "Ghost mode"
  private static let ghostModeToastPrefix = "Ghost mode is "
  /// Only the main menu has this item
  private static let mainMenuItemLabel = "My Profile"
  private static let backLabel = "Back"
  private static let moreOptionsLabel = "More options"
  /// Only the menu of a chat has this item
  private static let chatMenuItemLabel = "Select messages"
  private static let editLabel = "Edit"
  private static let contactFirstNameLabel = "First Name"
  private static let settingsTabLabel = "Settings"
  private static let goBackLabel = "Go back"
  private static let editProfileLabel = "Edit profile"
  private static let profileFirstNameLabel = "First name (required)"
  /// The only item of the settings menu; the test never taps it
  private static let logOutLabel = "Log Out"
  private static let attachLabel = "Add attachment"
  private static let attachMenuItemLabels = ["Photo or Video", "File"]
  private static let emojiButtonLabel = "Choose emoji, sticker or GIF"
  /// The tabs at the bottom of the emoji panel
  private static let symbolTabLabels = ["Emoji", "Stickers", "GIFs"]
  private static let mediaViewerCloseLabel = "Close"
  private static let messageMenuItemLabels = ["Reply", "Copy Text", "Pin", "Select", "Delete"]
  private static let replyLabel = "Reply"
  /// The button that removes the reply from the composer
  private static let cancelReplyLabel = "Cancel"
  private static let inAppBrowserButtonLabels = ["Close", "Done"]
  /// The page that `liquidgram-probe-open-later` opens, and its heading
  private static let openLaterHost = "example.com"
  private static let openLaterHeading = "Example Domain"
  private static let safariViewServiceBundleIdentifier = "com.apple.SafariViewService"
  /// SpringBoard shows the system's alerts, such as permission prompts
  private static let systemAlertsBundleIdentifier = "com.apple.springboard"

  // `Fixtures/ui-probe.js`
  private static let probeFixture = "ui-probe"
  private static let probeLabelPrefix = "liquidgram-probe "
  private static let probeBlurButtonLabel = "liquidgram-probe-blur"
  private static let probeOpenLaterButtonLabel = "liquidgram-probe-open-later"
  private static let probeTimeout: TimeInterval = 10

  /// A tap shows its result within this time
  private static let reactionTimeout: TimeInterval = 5
  /// Keyboard, menu and screen transitions take less than this
  private static let animationDelay: TimeInterval = 1
  /// The page calls `window.open` 1.5 s after the tap; Safari's view takes a moment to appear after that
  private static let inAppBrowserTimeout: TimeInterval = 12
  private static let keyboardCycles = 3
  private static let longPressDuration: TimeInterval = 1
  /// The app has turned within this time if it turns at all
  private static let rotationTimeout: TimeInterval = 3

  /// Frames of web content come from another process and may differ by rounding
  private static let frameTolerance: CGFloat = 1
  /// The status bar of an iPhone with a notch is at least this tall; used when SpringBoard does not report one
  private static let minimumStatusBarHeight: CGFloat = 44
  /// The buttons of a header start 8 to 12 pt below the top of the page
  private static let maxTopRowOffset: CGFloat = 24
  /// The composer sits right above the keyboard: the web app keeps a margin of 8 pt below its field
  private static let maxComposerGap: CGFloat = 24
  /// A drag on the messages that hides the keyboard, in points
  private static let listDragDistance: CGFloat = 200
  private static let listDragPressDuration: TimeInterval = 0.05
  /// Where a drag on the messages starts, as a share of the visible list from its top
  private static let listDragStart: CGFloat = 0.3
  /// A drag on the messages ends this far above the composer
  private static let listDragMargin: CGFloat = 16
  /// The photo is above its caption in the same bubble
  private static let photoTapOffset: CGFloat = 60
  /// A tap on the backdrop of a menu lands this far across the window from the side the menu is on, and this far
  /// down; the menus of the web app open next to their buttons, at one side of the screen
  private static let outsideTapSideShare: CGFloat = 0.85
  private static let outsideTapHeightShare: CGFloat = 0.55
  /// UIKit's bars above the keys, such as the predictions, belong to the keyboard as the app sees it. Their
  /// identifiers are not public API, so the keys' own frame is the fallback.
  private static let keyboardBarIdentifiers = ["SystemInputAssistantView", "inputView"]
  /// How far above the keys such a bar may start
  private static let maxKeyboardBarHeight: CGFloat = 120

  // The status bar strip
  /// A row at the very top of the strip, above the clock and the Dynamic Island
  private static let stripTopRow: CGFloat = 2
  /// A row this far above the bottom of the strip, below the status bar's content
  private static let stripBottomInset: CGFloat = 3
  /// Where the strip is sampled, as shares of the width; the rounded corners of the screen are left out
  private static let stripSamplePoints: [CGFloat] = stride(from: 0.1, through: 0.9, by: 0.05).map { CGFloat($0) }
  private static let colorTolerance = 10
  private static let minimumMatchingShare = 0.85

  // MARK: - Top rows

  /// The menu, search and ghost mode buttons of the chat list are below the status bar and react to a tap
  @MainActor
  func testChatListTopRowWorks() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    let menuButton = waitForHittable(webButtons(labeled: Self.menuButtonLabel), "the menu button of the chat list")
    let searchField = waitForHittable(textInputs(labeled: Self.searchLabel), "the search field of the chat list")
    let ghostButton = waitForHittable(webButtons(labeled: Self.ghostModeLabel), "the ghost mode button")
    attachScreenshot("01-chat-list")
    var problems = Problems()
    checkTopRow(
      [("Open menu", menuButton), ("The search field", searchField), ("Ghost mode", ghostButton)],
      &problems
    )

    let menuButtonFrame = menuButton.frame
    tapCenter(of: menuButton)
    if let item = findHittable(labeled: Self.mainMenuItemLabel, timeout: Self.reactionTimeout) {
      attachScreenshot("02-main-menu")
      closeMenu(around: item, "the main menu", &problems)
    } else {
      problems.add("A tap on Open menu at \(Self.describe(menuButtonFrame)) did not open the main menu")
    }

    if let searchField = findHittable(in: textInputs(labeled: Self.searchLabel), timeout: Self.reactionTimeout) {
      let searchFieldFrame = searchField.frame
      tapCenter(of: searchField)
      if waitUntil(timeout: Self.reactionTimeout, { keyboard.exists }) {
        attachScreenshot("03-search")
        if let returnButton = findHittable(labeled: Self.returnToChatListLabel, timeout: Self.reactionTimeout) {
          tapCenter(of: returnButton)
          problems.check(
            waitUntil(timeout: Self.reactionTimeout, { !keyboard.exists }),
            "Return to chat list left the keyboard of the search up"
          )
        } else {
          problems.add("The search has no Return to chat list button")
        }
      } else {
        problems.add("A tap on the search field at \(Self.describe(searchFieldFrame)) brought up no keyboard")
      }
    } else {
      problems.add("The search field left the screen after the main menu")
    }

    if let ghostButton = findHittable(in: webButtons(labeled: Self.ghostModeLabel), timeout: Self.reactionTimeout) {
      let ghostButtonFrame = ghostButton.frame
      tapCenter(of: ghostButton)
      problems.check(
        findElement(in: webView, labelContaining: Self.ghostModeToastPrefix)
          .waitForExistence(timeout: Self.reactionTimeout),
        "A tap on Ghost mode at \(Self.describe(ghostButtonFrame)) showed no toast"
      )
      attachScreenshot("04-ghost-mode")
    } else {
      problems.add("Ghost mode left the screen after the search")
    }
    assertNoProblems(problems, "The top row of the chat list")
  }

  /// Back, the title and More options of an open chat are below the status bar and react to a tap
  @MainActor
  func testChatTopRowWorks() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    let composer = openChat(titled: Self.demoChatTitle)
    let back = waitForHittable(webButtons(labeled: Self.backLabel), "the Back button of the chat")
    let title = waitForHittable(webButtons(labeled: Self.demoChatTitle), "the title of the chat")
    let more = waitForHittable(webButtons(labeled: Self.moreOptionsLabel), "the More options button of the chat")
    attachScreenshot("01-chat")
    var problems = Problems()
    checkTopRow([("Back", back), ("The chat title", title), ("More options", more)], &problems)

    let moreFrame = more.frame
    tapCenter(of: more)
    if let item = findHittable(labeled: Self.chatMenuItemLabel, timeout: Self.reactionTimeout) {
      attachScreenshot("02-chat-menu")
      closeMenu(around: item, "the chat menu", &problems)
    } else {
      problems.add("A tap on More options at \(Self.describe(moreFrame)) did not open the menu of the chat")
    }

    let titleQuery = webButtons(labeled: Self.demoChatTitle)
    guard let currentTitle = findHittable(in: titleQuery, timeout: Self.reactionTimeout) else {
      problems.add("The chat title left the screen after the menu of the chat")
      assertNoProblems(problems, "The top row of a chat")
      return
    }
    let titleFrame = currentTitle.frame
    tapCenter(of: currentTitle)
    if let edit = findHittable(labeled: Self.editLabel, timeout: Self.reactionTimeout) {
      attachScreenshot("03-profile")
      if let profileBack = findHittable(labeled: Self.backLabel, timeout: Self.reactionTimeout) {
        tapCenter(of: profileBack)
        problems.check(
          waitUntil(timeout: Self.reactionTimeout, { isOnScreen(composer) && !isOnScreen(edit) }),
          "Back in the profile did not return to the chat"
        )
      }
    } else {
      problems.add("A tap on the chat title at \(Self.describe(titleFrame)) did not open the profile")
    }

    guard let chatBack = findHittable(in: webButtons(labeled: Self.backLabel), timeout: Self.reactionTimeout) else {
      problems.add("The chat lost its Back button after the profile")
      assertNoProblems(problems, "The top row of a chat")
      return
    }
    let chatBackFrame = chatBack.frame
    tapCenter(of: chatBack)
    problems.check(
      waitUntil(timeout: Self.reactionTimeout, { !isOnScreen(composer) && isChatRowHittable(Self.demoChatTitle) }),
      "A tap on Back at \(Self.describe(chatBackFrame)) did not return to the chat list"
    )
    attachScreenshot("04-chat-list-after-back")
    assertNoProblems(problems, "The top row of a chat")
  }

  /// Back and Edit of a profile are below the status bar and react to a tap
  @MainActor
  func testProfileTopRowWorks() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    let composer = openChat(titled: Self.demoChatTitle)
    let title = waitForHittable(webButtons(labeled: Self.demoChatTitle), "the title of the chat")
    let titleFrame = title.frame
    tapCenter(of: title)
    var problems = Problems()
    // The title is the way to the profile, so a title that does not react leaves nothing else to check
    guard let edit = findHittable(in: webButtons(labeled: Self.editLabel), timeout: Self.reactionTimeout) else {
      checkTopRow([("The chat title", title)], &problems)
      problems.add("A tap on the chat title at \(Self.describe(titleFrame)) did not open the profile")
      assertNoProblems(problems, "The top row of a profile")
      return
    }
    let back = waitForHittable(webButtons(labeled: Self.backLabel), "the Back button of the profile")
    attachScreenshot("01-profile")
    checkTopRow([("Back", back), ("Edit", edit)], &problems)

    let editFrame = edit.frame
    tapCenter(of: edit)
    if findHittable(in: textInputs(labeled: Self.contactFirstNameLabel), timeout: Self.reactionTimeout) != nil {
      attachScreenshot("02-edit-contact")
      if let editBack = findHittable(labeled: Self.backLabel, timeout: Self.reactionTimeout) {
        tapCenter(of: editBack)
      }
      problems.check(
        findHittable(labeled: Self.editLabel, timeout: Self.reactionTimeout) != nil,
        "Back on the contact editor did not return to the profile"
      )
    } else {
      problems.add("A tap on Edit at \(Self.describe(editFrame)) did not open the contact editor")
    }

    if let profileBack = findHittable(labeled: Self.backLabel, timeout: Self.reactionTimeout) {
      let profileBackFrame = profileBack.frame
      tapCenter(of: profileBack)
      problems.check(
        waitUntil(timeout: Self.reactionTimeout, { isOnScreen(composer) }),
        "A tap on Back at \(Self.describe(profileBackFrame)) did not close the profile"
      )
    } else {
      problems.add("The profile lost its Back button")
    }
    attachScreenshot("03-chat-after-back")
    assertNoProblems(problems, "The top row of a profile")
  }

  /// Go back, Search, Edit profile and More options of the settings are below the status bar and react to a tap
  @MainActor
  func testSettingsTopRowWorks() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    tapCenter(of: waitForHittable(webButtons(labeled: Self.settingsTabLabel), "the Settings tab"))
    allowNotificationsIfAsked()
    let goBack = waitForHittable(webButtons(labeled: Self.goBackLabel), "the Go back button of the settings")
    let search = waitForHittable(webButtons(labeled: Self.searchLabel), "the Search button of the settings")
    let editProfile = waitForHittable(webButtons(labeled: Self.editProfileLabel), "the Edit profile button")
    let more = waitForHittable(webButtons(labeled: Self.moreOptionsLabel), "the More options button of the settings")
    attachScreenshot("01-settings")
    var problems = Problems()
    checkTopRow(
      [("Go back", goBack), ("Search", search), ("Edit profile", editProfile), ("More options", more)],
      &problems
    )

    let moreFrame = more.frame
    tapCenter(of: more)
    if let logOut = findHittable(labeled: Self.logOutLabel, timeout: Self.reactionTimeout) {
      attachScreenshot("02-settings-menu")
      closeMenu(around: logOut, "the settings menu", &problems)
    } else {
      problems.add("A tap on More options at \(Self.describe(moreFrame)) did not open the settings menu")
    }

    let searchFrame = search.frame
    tapCenter(of: search)
    let isSearchShown = waitUntil(timeout: Self.reactionTimeout) {
      !isOnScreen(editProfile)
        && textInputs(labeled: Self.searchLabel).allElementsBoundByIndex.contains { $0.isHittable }
    }
    if isSearchShown {
      attachScreenshot("03-settings-search")
      returnToSettings(from: "the settings search", &problems)
    } else {
      problems.add("A tap on Search at \(Self.describe(searchFrame)) did not open the settings search")
    }

    if let currentEditProfile = findHittable(labeled: Self.editProfileLabel, timeout: Self.reactionTimeout) {
      let editProfileFrame = currentEditProfile.frame
      tapCenter(of: currentEditProfile)
      if findHittable(in: textInputs(labeled: Self.profileFirstNameLabel), timeout: Self.reactionTimeout) != nil {
        attachScreenshot("04-edit-profile")
        returnToSettings(from: "the profile editor", &problems)
      } else {
        problems.add("A tap on Edit profile at \(Self.describe(editProfileFrame)) did not open the profile editor")
      }
    } else {
      problems.add("Edit profile is not on screen after the settings search")
    }

    if let settingsBack = findHittable(labeled: Self.goBackLabel, timeout: Self.reactionTimeout) {
      let settingsBackFrame = settingsBack.frame
      tapCenter(of: settingsBack)
      problems.check(
        waitUntil(timeout: Self.reactionTimeout, { isChatRowHittable(Self.demoChatTitle) }),
        "A tap on Go back at \(Self.describe(settingsBackFrame)) did not return to the chat list"
      )
    } else {
      problems.add("The settings lost their Go back button")
    }
    attachScreenshot("05-chat-list")
    assertNoProblems(problems, "The top row of the settings")
  }

  // MARK: - Keyboard

  /// With the keyboard up the page ends at the keyboard instead of sliding up: the header stays, the composer sits
  /// right above the keyboard and the newest message above the composer. When the keyboard hides, every frame is
  /// back where it was, also after a few more keyboard cycles, and the page itself never scrolled.
  @MainActor
  func testKeyboardKeepsChatLayout() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, fixtures: [Self.probeFixture]))
    let composer = openChat(titled: Self.demoChatTitle)
    let back = waitForHittable(webButtons(labeled: Self.backLabel), "the Back button of the chat")
    let newest = waitForHittable(
      webView.staticTexts.matching(Self.makeLabelPredicate(containing: Self.newestMessage)),
      "the newest message"
    )
    pause(Self.animationDelay)
    let layoutBefore = measureChatLayout(back: back, composer: composer, newest: newest)
    attachScreenshot("01-chat")
    var problems = Problems()

    tapCenter(of: composer)
    waitFor(keyboard, "the keyboard of the composer")
    dismissKeyboardIntroductionIfShown()
    app.typeText(Self.typedText)
    pause(Self.animationDelay)
    let keyboardTop = keyboardTopEdge ?? keyboard.frame.minY
    let layoutWithKeyboard = measureChatLayout(back: back, composer: composer, newest: newest)
    attachScreenshot("02-keyboard")
    problems.check(
      layoutWithKeyboard.webView.maxY <= keyboardTop + Self.frameTolerance,
      "The page goes on under the keyboard: it ends at y \(Int(layoutWithKeyboard.webView.maxY)), the keyboard "
        + "starts at y \(Int(keyboardTop))"
    )
    problems.check(
      isOnScreen(back) && Self.isSameFrame(layoutWithKeyboard.back, layoutBefore.back),
      "The header moved with the keyboard: Back is at \(Self.describe(layoutWithKeyboard.back)) instead of "
        + Self.describe(layoutBefore.back)
    )
    problems.check(
      layoutWithKeyboard.composer.maxY <= keyboardTop + Self.frameTolerance
        && keyboardTop - layoutWithKeyboard.composer.maxY <= Self.maxComposerGap,
      "The composer at \(Self.describe(layoutWithKeyboard.composer)) is not right above the keyboard at y "
        + "\(Int(keyboardTop))"
    )
    problems.check(
      isOnScreen(newest)
        && layoutWithKeyboard.newest.maxY <= layoutWithKeyboard.composer.minY + Self.frameTolerance
        && layoutWithKeyboard.newest.minY >= layoutWithKeyboard.back.maxY - Self.frameTolerance,
      "The newest message at \(Self.describe(layoutWithKeyboard.newest)) is not between the header and the composer "
        + "at \(Self.describe(layoutWithKeyboard.composer))"
    )
    if let probe = waitForProbe("the page with the keyboard up", until: { _ in true }) {
      problems.check(
        Self.isPageUnscrolled(probe.scrollTop, probe.scrollY, probe.pageTop, probe.offsetTop),
        "The page scrolled with the keyboard: pageTop \(probe.pageTop), offsetTop \(probe.offsetTop), scrollTop "
          + "\(probe.scrollTop), scrollY \(probe.scrollY)"
      )
    }

    hideKeyboardThroughProbe(&problems)
    let layoutAfter = measureChatLayout(back: back, composer: composer, newest: newest)
    attachScreenshot("03-keyboard-hidden")
    for difference in layoutAfter.describeDifferences(from: layoutBefore) {
      problems.add("After the keyboard hid, \(difference)")
    }

    for _ in 1 ..< Self.keyboardCycles {
      tapCenter(of: composer)
      _ = waitUntil(timeout: Self.reactionTimeout, { keyboard.exists })
      pause(Self.animationDelay)
      hideKeyboardThroughProbe(&problems)
    }
    let layoutAfterCycles = measureChatLayout(back: back, composer: composer, newest: newest)
    attachScreenshot("04-after-keyboard-cycles")
    for difference in layoutAfterCycles.describeDifferences(from: layoutBefore) {
      problems.add("After \(Self.keyboardCycles) keyboard cycles, \(difference)")
    }
    if let probe = waitForProbe("the page after the keyboard cycles", until: { _ in true }) {
      problems.check(
        Self.isPageUnscrolled(probe.max.scrollTop, probe.max.scrollY, probe.max.pageTop, probe.max.offsetTop),
        "The page scrolled during the keyboard cycles: highest pageTop \(probe.max.pageTop), offsetTop "
          + "\(probe.max.offsetTop), scrollTop \(probe.max.scrollTop), scrollY \(probe.max.scrollY)"
      )
      let viewportHeight = probe.vh ?? probe.innerHeight
      problems.check(
        abs(probe.htmlHeight - probe.innerHeight) <= Self.frameTolerance
          && abs(viewportHeight - probe.innerHeight) <= Self.frameTolerance
          && abs(probe.visualHeight - probe.innerHeight) <= Self.frameTolerance,
        "The page does not fit the screen after the keyboard cycles: root \(probe.htmlHeight), --vh×100 "
          + "\(viewportHeight), visual viewport \(probe.visualHeight), window \(probe.innerHeight)"
      )
    }
    assertNoProblems(problems, "The chat with the keyboard")
  }

  /// Dragging the messages down hides the keyboard, as in Telegram
  @MainActor
  func testDraggingMessagesHidesKeyboard() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    let composer = openChat(titled: Self.demoChatTitle)
    tapCenter(of: composer)
    waitFor(keyboard, "the keyboard of the composer")
    dismissKeyboardIntroductionIfShown()
    pause(Self.animationDelay)
    attachScreenshot("01-keyboard-up")

    // The part of the message list that is on screen: below the header, or the status bar if the header left the
    // screen, and above the composer
    let back = webButtons(labeled: Self.backLabel).allElementsBoundByIndex.first { $0.isHittable }
    let listTop = max(back?.frame.maxY ?? 0, statusBarBottom)
    let listBottom = composer.frame.minY
    let start = CGPoint(x: app.windows.firstMatch.frame.midX, y: listTop + (listBottom - listTop) * Self.listDragStart)
    let end = CGPoint(x: start.x, y: min(start.y + Self.listDragDistance, listBottom - Self.listDragMargin))
    screenCoordinate(start).press(forDuration: Self.listDragPressDuration, thenDragTo: screenCoordinate(end))
    let isHidden = waitUntil(timeout: Self.reactionTimeout, { !keyboard.exists })
    attachScreenshot("02-after-drag")
    if !isHidden {
      failWithEvidence(
        "The keyboard stayed up after a drag down on the messages from y \(Int(start.y)) to y \(Int(end.y))"
      )
    }
  }

  // MARK: - Screen

  /// On a turned iPhone the app stays in portrait instead of switching to the tablet layout
  @MainActor
  func testAppStaysPortrait() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, fixtures: [Self.probeFixture]))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    let portraitFrame = app.windows.firstMatch.frame
    attachScreenshot("01-portrait")

    // Nothing fails while the simulator is turned, so the test always turns it back. The window, as XCUITest reports
    // it, and the page's own viewport both tell whether the app turned.
    XCUIDevice.shared.orientation = .landscapeLeft
    var probe: PageProbe?
    let hasTurned = waitUntil(timeout: Self.rotationTimeout) {
      let frame = app.windows.firstMatch.frame
      probe = readProbe()
      return frame.width > frame.height || (probe.map { $0.innerWidth > $0.innerHeight } ?? false)
    }
    let turnedFrame = app.windows.firstMatch.frame
    attachScreenshot("02-device-turned")
    XCUIDevice.shared.orientation = .portrait

    if hasTurned {
      let viewport = probe.map { " and the page is \(Int($0.innerWidth))×\(Int($0.innerHeight))" } ?? ""
      failWithEvidence(
        "The app turned to landscape with the device: its window is \(Self.describe(turnedFrame)) instead of "
          + Self.describe(portraitFrame) + viewport
      )
    }
  }

  /// The strip behind the status bar has the theme color of the page, in the light and the dark theme, instead of
  /// showing the page under the clock
  @MainActor
  func testStatusBarStripMatchesTheme() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, fixtures: [Self.probeFixture]))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    guard let probe = waitForProbe("the theme color of the page", until: { $0.themeColor != nil }),
          let themeColorText = probe.themeColor else {
      return
    }
    guard let themeColor = RGBColor(hex: themeColorText) else {
      failWithEvidence("The theme color \(themeColorText) of the page is not a hex color")
      return
    }
    // The status bar text follows the theme color once the page has set it
    pause(Self.animationDelay)
    let pageTop = webView.frame.minY
    let stripBottom = max(pageTop, statusBarBottom)
    attachScreenshot("01-status-bar-strip")
    var problems = Problems()
    problems.check(
      pageTop >= statusBarBottom - Self.frameTolerance,
      "The page starts at y \(Int(pageTop)), under the status bar, which ends at y \(Int(statusBarBottom)), so the "
        + "status bar shows the page instead of a strip in the theme color"
    )

    let windowWidth = app.windows.firstMatch.frame.width
    let screenshot = XCUIScreen.main.screenshot()
    guard let pixels = ScreenPixels(image: screenshot.image.cgImage, pointWidth: windowWidth) else {
      failWithEvidence("The screenshot has no bitmap to read")
      return
    }
    let xs = Self.stripSamplePoints.map { $0 * windowWidth }
    for row in [Self.stripTopRow, stripBottom - Self.stripBottomInset] {
      guard let colors = pixels.readColors(atY: row, xs: xs) else {
        problems.add("The screenshot has no row at y \(Int(row))")
        continue
      }
      let matchingCount = colors.filter { $0.isClose(to: themeColor, tolerance: Self.colorTolerance) }.count
      problems.check(
        Double(matchingCount) >= Double(colors.count) * Self.minimumMatchingShare,
        "The strip at y \(Int(row)) shows \(RGBColor.describe(colors)) instead of the theme color \(themeColorText)"
      )
    }
    assertNoProblems(problems, "The status bar strip in the \(probe.theme ?? "unknown") theme")
  }

  /// Animations and the connection indicator run right after the start, before anything is touched: the page counts
  /// as focused, not as being in the background
  @MainActor
  func testPageIsActiveBeforeFirstTap() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, fixtures: [Self.probeFixture]))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    pause(Self.animationDelay)
    guard let probe = waitForProbe("the state of the page", until: { _ in true }) else {
      return
    }
    attachScreenshot("01-chat-list-untouched")
    if probe.isInBackground {
      failWithEvidence(
        "The page treats itself as being in the background until the first tap (body.in-background; "
          + "document.hasFocus() is \(probe.hasFocus)), so its animations stand still"
      )
    }
  }

  /// The attach menu and the emoji panel open and are entirely on screen, above the home indicator
  @MainActor
  func testAttachMenuAndEmojiPanelFitOnScreen() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, fixtures: [Self.probeFixture]))
    let composer = openChat(titled: Self.demoChatTitle)
    guard let probe = waitForProbe("the safe area of the page", until: { _ in true }) else {
      return
    }
    let window = app.windows.firstMatch.frame
    let homeIndicatorTop = window.maxY - probe.safeBottom
    var problems = Problems()

    let attachButton = waitForHittable(webElements(labeled: Self.attachLabel), "the attach button")
    let attachButtonFrame = attachButton.frame
    tapCenter(of: attachButton)
    let attachItems = Self.attachMenuItemLabels.compactMap { label in
      findHittable(labeled: label, timeout: Self.reactionTimeout).map { (label: label, element: $0) }
    }
    if let firstItem = attachItems.first {
      attachScreenshot("01-attach-menu")
      for item in attachItems {
        checkOnScreen("The attach menu item \(item.label)", item.element.frame, above: homeIndicatorTop, &problems)
      }
      closeMenu(around: firstItem.element, "the attach menu", &problems)
    } else {
      problems.add("A tap on the attach button at \(Self.describe(attachButtonFrame)) did not open the attach menu")
    }

    let emojiButtonQuery = webButtons(labeled: Self.emojiButtonLabel)
    guard let emojiButton = findHittable(in: emojiButtonQuery, timeout: Self.reactionTimeout) else {
      problems.add("The emoji button is not on screen after the attach menu")
      assertNoProblems(problems, "The panels of the composer")
      return
    }
    let emojiButtonFrame = emojiButton.frame
    tapCenter(of: emojiButton)
    let tabs = Self.symbolTabLabels.compactMap { label in
      findHittable(labeled: label, timeout: Self.reactionTimeout).map { (label: label, element: $0) }
    }
    if tabs.isEmpty {
      problems.add("A tap on the emoji button at \(Self.describe(emojiButtonFrame)) did not open the emoji panel")
    } else {
      pause(Self.animationDelay)
      attachScreenshot("02-emoji-panel")
      for tab in tabs {
        checkOnScreen("The \(tab.label) tab of the emoji panel", tab.element.frame, above: homeIndicatorTop, &problems)
      }
      let panelTop = tabs.map { $0.element.frame.minY }.min() ?? window.maxY
      problems.check(
        isOnScreen(composer) && composer.frame.maxY <= panelTop,
        "The composer at \(Self.describe(composer.frame)) is not above the emoji panel"
      )
    }
    assertNoProblems(problems, "The panels of the composer")
  }

  // MARK: - Media and menus

  /// A tap on a photo opens the media viewer, whose Close button is below the status bar and closes it
  @MainActor
  func testMediaViewerOpensAndCloses() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    let composer = openChat(titled: Self.photoChatTitle)
    let caption = waitForHittable(
      webView.staticTexts.matching(Self.makeLabelPredicate(containing: Self.photoCaption)),
      "the caption of the photo"
    )
    attachScreenshot("01-chat-with-photo")
    tapScreen(at: CGPoint(x: caption.frame.midX, y: caption.frame.minY - Self.photoTapOffset))
    let close = waitForHittable(
      webButtons(labeled: Self.mediaViewerCloseLabel),
      "the media viewer with its Close button"
    )
    pause(Self.animationDelay)
    attachScreenshot("02-media-viewer")
    var problems = Problems()
    checkTopRow([("The Close button of the media viewer", close)], &problems)

    let closeFrame = close.frame
    tapCenter(of: close)
    problems.check(
      waitUntil(timeout: Self.reactionTimeout, {
        isOnScreen(composer) && !webButtons(labeled: Self.mediaViewerCloseLabel).allElementsBoundByIndex.contains {
          $0.isHittable
        }
      }),
      "A tap on Close at \(Self.describe(closeFrame)) did not close the media viewer"
    )
    attachScreenshot("03-media-viewer-closed")
    assertNoProblems(problems, "The media viewer")
  }

  /// A long press on a message opens its menu on screen, and the first tap on Reply works
  @MainActor
  func testLongPressOnMessageOpensMenu() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    openChat(titled: Self.demoChatTitle)
    let message = waitForHittable(
      webView.staticTexts.matching(Self.makeLabelPredicate(containing: Self.middleMessage)),
      "a message of the chat"
    )
    message.press(forDuration: Self.longPressDuration)
    let reply = waitForHittable(webElements(labeled: Self.replyLabel), "the menu of the message after a long press")
    pause(Self.animationDelay)
    attachScreenshot("01-message-menu")
    var problems = Problems()
    let window = app.windows.firstMatch.frame
    for label in Self.messageMenuItemLabels {
      guard let item = findHittable(labeled: label, timeout: 0) else {
        continue
      }
      checkOnScreen("The menu item \(label)", item.frame, above: window.maxY, &problems)
    }

    tapCenter(of: reply)
    problems.check(
      waitUntil(timeout: Self.reactionTimeout, { !isOnScreen(reply) }),
      "The first tap on Reply did not close the menu"
    )
    problems.check(
      findHittable(labeled: Self.cancelReplyLabel, timeout: Self.reactionTimeout) != nil,
      "The first tap on Reply did not start a reply above the composer"
    )
    attachScreenshot("02-reply")
    assertNoProblems(problems, "The menu of a message")
  }

  /// A link that the page opens a while after the tap, after the server answered, still reaches the in-app browser
  @MainActor
  func testDelayedWindowOpenShowsInAppBrowser() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true, fixtures: [Self.probeFixture]))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list")
    tapProbeButton(Self.probeOpenLaterButtonLabel)
    var closeButton: XCUIElement?
    let isShown = waitUntil(timeout: Self.inAppBrowserTimeout) {
      closeButton = findInAppBrowserButton()
      return closeButton != nil || isInAppBrowserAddressShown || isPageCoveredInForeground
    }
    attachScreenshot("01-in-app-browser")
    guard isShown else {
      failWithEvidence(
        "No in-app browser within \(Int(Self.inAppBrowserTimeout)) s after the page called window.open 1.5 s "
          + "after a tap"
      )
      return
    }
    // Only for the report: the test is about the browser opening
    if let closeButton {
      closeButton.tap()
      _ = waitUntil(timeout: Self.reactionTimeout, { isChatRowHittable(Self.demoChatTitle) })
      attachScreenshot("02-in-app-browser-closed")
    }
  }

  // MARK: - Helpers

  @MainActor
  private func measureChatLayout(back: XCUIElement, composer: XCUIElement, newest: XCUIElement) -> ChatLayout {
    ChatLayout(webView: webView.frame, back: back.frame, composer: composer.frame, newest: newest.frame)
  }

  /// Opens a chat of the chat list and returns its composer
  @MainActor
  @discardableResult
  private func openChat(titled title: String) -> XCUIElement {
    waitForChatRow(titled: title, "the chat \(title) in the chat list").tap()
    allowNotificationsIfAsked()
    return waitForHittable(textInputs(labeled: Self.composerLabel), "the composer of the chat \(title)")
  }

  /// Whether an element exists and can be tapped; false, without failing, for one that is gone
  @MainActor
  private func isOnScreen(_ element: XCUIElement) -> Bool {
    element.exists && element.isHittable
  }

  @MainActor
  private func isChatRowHittable(_ title: String) -> Bool {
    findElements(in: webView, labelContaining: title).allElementsBoundByIndex.contains { $0.isHittable }
  }

  /// Web content of any type with exactly this label
  @MainActor
  private func webElements(labeled label: String) -> XCUIElementQuery {
    webView.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label))
  }

  @MainActor
  private func webButtons(labeled label: String) -> XCUIElementQuery {
    webView.buttons.matching(NSPredicate(format: "label == %@", label))
  }

  /// Text fields and text views with this label or placeholder, like `findTextInput(in:labeled:)` but every match
  @MainActor
  private func textInputs(labeled label: String) -> XCUIElementQuery {
    let types = [XCUIElement.ElementType.textField, .textView, .searchField].map { NSNumber(value: $0.rawValue) }
    let predicate = NSPredicate(
      format: "(label == %@ OR placeholderValue == %@) AND elementType IN %@",
      label,
      label,
      types as NSArray
    )
    return webView.descendants(matching: .any).matching(predicate)
  }

  /// The first element of `query` that can be tapped within `timeout`, or nil, without failing
  @MainActor
  private func findHittable(in query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
    var match: XCUIElement?
    _ = waitUntil(timeout: timeout) {
      match = query.allElementsBoundByIndex.first { $0.isHittable }
      return match != nil
    }
    return match
  }

  @MainActor
  private func findHittable(labeled label: String, timeout: TimeInterval) -> XCUIElement? {
    findHittable(in: webElements(labeled: label), timeout: timeout)
  }

  /// Taps the center of an element the way a finger does, also where XCUITest would refuse a tap on it, such as under
  /// the status bar
  @MainActor
  private func tapCenter(of element: XCUIElement) {
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
  }

  @MainActor
  private func screenCoordinate(_ point: CGPoint) -> XCUICoordinate {
    app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
  }

  @MainActor
  private func tapScreen(at point: CGPoint) {
    screenCoordinate(point).tap()
  }

  /// Closes a menu of the web app with a tap on its backdrop, on the other side of the screen than `item`
  @MainActor
  private func closeMenu(around item: XCUIElement, _ name: String, _ problems: inout Problems) {
    let window = app.windows.firstMatch.frame
    let sideShare = item.frame.midX < window.midX ? Self.outsideTapSideShare : 1 - Self.outsideTapSideShare
    tapScreen(at: CGPoint(x: window.width * sideShare, y: window.height * Self.outsideTapHeightShare))
    problems.check(
      waitUntil(timeout: Self.reactionTimeout, { !item.isHittable }),
      "A tap outside \(name) did not close it"
    )
  }

  /// From a screen of the settings back to their main screen, with the Go back button
  @MainActor
  private func returnToSettings(from screen: String, _ problems: inout Problems) {
    guard let goBack = findHittable(labeled: Self.goBackLabel, timeout: Self.reactionTimeout) else {
      problems.add("\(screen) has no Go back button")
      return
    }
    tapCenter(of: goBack)
    problems.check(
      findHittable(labeled: Self.editProfileLabel, timeout: Self.reactionTimeout) != nil,
      "Go back on \(screen) did not return to the settings"
    )
  }

  /// The bottom of the status bar, which no control may overlap
  @MainActor
  private var statusBarBottom: CGFloat {
    max(statusBarFrame.maxY, Self.minimumStatusBarHeight)
  }

  /// Records controls of a top row that are under the status bar, or further down the page than a header puts them,
  /// as when the page adds a top inset of its own below the status bar
  @MainActor
  private func checkTopRow(_ controls: [(name: String, element: XCUIElement)], _ problems: inout Problems) {
    let limit = statusBarBottom
    let pageTop = webView.frame.minY
    for control in controls {
      let frame = control.element.frame
      problems.check(
        frame.minY >= limit - Self.frameTolerance,
        "\(control.name) at \(Self.describe(frame)) is under the status bar, which ends at y \(Int(limit))"
      )
      problems.check(
        frame.minY - pageTop <= Self.maxTopRowOffset,
        "\(control.name) at \(Self.describe(frame)) is \(Int(frame.minY - pageTop)) pt below the top of the page at "
          + "y \(Int(pageTop)), so the page adds a top inset of its own"
      )
    }
  }

  /// Records an element that is not entirely between the status bar and `bottom`
  @MainActor
  private func checkOnScreen(_ name: String, _ frame: CGRect, above bottom: CGFloat, _ problems: inout Problems) {
    problems.check(
      frame.minY >= statusBarBottom - Self.frameTolerance && frame.maxY <= bottom + Self.frameTolerance,
      "\(name) at \(Self.describe(frame)) is not entirely between the status bar and y \(Int(bottom))"
    )
  }

  /// The top of the keyboard together with the bars above its keys; nil while no keyboard is shown
  @MainActor
  private var keyboardTopEdge: CGFloat? {
    let keys = keyboard
    guard keys.exists, keys.frame.height > 0 else {
      return nil
    }
    var top = keys.frame.minY
    for identifier in Self.keyboardBarIdentifiers {
      let bar = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
      guard bar.exists else {
        continue
      }
      let barTop = bar.frame.minY
      if bar.frame.height > 0, barTop < top, barTop >= keys.frame.minY - Self.maxKeyboardBarHeight {
        top = barTop
      }
    }
    return top
  }

  /// Hides the keyboard by taking the focus from the composer through the probe, which works on every build
  @MainActor
  private func hideKeyboardThroughProbe(_ problems: inout Problems) {
    tapProbeButton(Self.probeBlurButtonLabel)
    problems.check(
      waitUntil(timeout: Self.reactionTimeout, { !keyboard.exists }),
      "The keyboard stayed up after the composer lost the focus"
    )
    pause(Self.animationDelay)
  }

  /// The measurements of `Fixtures/ui-probe.js`, or nil before it reports
  @MainActor
  private func readProbe() -> PageProbe? {
    let element = webView.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", Self.probeLabelPrefix))
      .firstMatch
    guard element.exists else {
      return nil
    }
    let label = element.label
    guard label.hasPrefix(Self.probeLabelPrefix) else {
      return nil
    }
    return try? JSONDecoder().decode(PageProbe.self, from: Data(label.dropFirst(Self.probeLabelPrefix.count).utf8))
  }

  /// Waits until the probe reports a state that `condition` accepts; fails and returns nil when it does not
  @MainActor
  private func waitForProbe(
    _ description: String,
    file: StaticString = #filePath,
    line: UInt = #line,
    until condition: (PageProbe) -> Bool
  ) -> PageProbe? {
    var probe: PageProbe?
    let isReported = waitUntil(timeout: Self.probeTimeout) {
      probe = readProbe()
      return probe.map(condition) ?? false
    }
    if !isReported {
      failWithEvidence(
        "The page probe did not report \(description) within \(Int(Self.probeTimeout)) s",
        file: file,
        line: line
      )
      return nil
    }
    return probe
  }

  /// Taps a button of `Fixtures/ui-probe.js`, which runs page code that a test cannot run itself
  @MainActor
  private func tapProbeButton(_ label: String) {
    tapCenter(of: waitForHittable(webButtons(labeled: label), "the probe button \(label)"))
  }

  /// Safari's view controller runs in its own process; XCUITest sees its buttons in the app or in that process
  @MainActor
  private func findInAppBrowserButton() -> XCUIElement? {
    let safariViewService = XCUIApplication(bundleIdentifier: Self.safariViewServiceBundleIdentifier)
    for root in [app, safariViewService] {
      for label in Self.inAppBrowserButtonLabels {
        let button = root.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        // The web app's own buttons are inside the web view, which Safari's view covers
        if button.exists, button.isHittable, !webView.isHittable {
          return button
        }
      }
    }
    return nil
  }

  /// Whether Safari's view shows the host or the heading of the page that the probe opened
  @MainActor
  private var isInAppBrowserAddressShown: Bool {
    let predicate = NSPredicate(
      format: "label CONTAINS %@ OR value CONTAINS %@ OR label CONTAINS %@",
      Self.openLaterHost,
      Self.openLaterHost,
      Self.openLaterHeading
    )
    return app.descendants(matching: .any).matching(predicate).firstMatch.exists
  }

  /// Whether a view of the app covers the page while the app stays in front, as Safari's view does where XCUITest
  /// cannot see into it; a system alert does not count
  @MainActor
  private var isPageCoveredInForeground: Bool {
    let systemAlert = XCUIApplication(bundleIdentifier: Self.systemAlertsBundleIdentifier).alerts.firstMatch
    return app.state == .runningForeground && !webView.isHittable && !systemAlert.exists
  }

  /// Fails with the screen and the accessibility tree attached
  @MainActor
  private func failWithEvidence(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
    let name = "failure-" + Self.makeSlug(message)
    attachScreenshot(name)
    attachAccessibilityTree(name)
    XCTFail(message, file: file, line: line)
  }

  @MainActor
  private func assertNoProblems(
    _ problems: Problems,
    _ subject: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    guard !problems.isEmpty else {
      return
    }
    failWithEvidence("\(subject): " + problems.messages.joined(separator: "; "), file: file, line: line)
  }

  private static func isPageUnscrolled(_ offsets: CGFloat...) -> Bool {
    offsets.allSatisfy { abs($0) < frameTolerance }
  }

  fileprivate static func isSameFrame(_ frame: CGRect, _ other: CGRect) -> Bool {
    abs(frame.minX - other.minX) <= frameTolerance
      && abs(frame.minY - other.minY) <= frameTolerance
      && abs(frame.width - other.width) <= frameTolerance
      && abs(frame.height - other.height) <= frameTolerance
  }

  fileprivate static func isSameVerticalPlace(_ frame: CGRect, _ other: CGRect) -> Bool {
    abs(frame.minY - other.minY) <= frameTolerance && abs(frame.maxY - other.maxY) <= frameTolerance
  }

  fileprivate static func describe(_ frame: CGRect) -> String {
    "(\(Int(frame.minX)), \(Int(frame.minY)), \(Int(frame.width))×\(Int(frame.height)))"
  }

  /// The first words of a message as a file name for its attachments
  private static func makeSlug(_ text: String) -> String {
    let maxLength = 48
    let words = text.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty && $0.unicodeScalars.allSatisfy(\.isASCII) }
    var slug = ""
    for word in words {
      let nextSlug = slug.isEmpty ? word : "\(slug)-\(word)"
      guard nextSlug.count <= maxLength else {
        break
      }
      slug = nextSlug
    }
    return slug
  }
}

/// The problems that a test found. It collects them and fails once at the end, so the report names all of them.
private struct Problems {
  private(set) var messages: [String] = []

  var isEmpty: Bool {
    messages.isEmpty
  }

  mutating func add(_ message: String) {
    messages.append(message)
  }

  mutating func check(_ condition: Bool, _ message: @autoclosure () -> String) {
    if !condition {
      messages.append(message())
    }
  }
}

/// Where the parts of an open chat are on screen
private struct ChatLayout {
  let webView: CGRect
  let back: CGRect
  let composer: CGRect
  let newest: CGRect

  /// What moved compared with `other`. The composer may change its width when it gets text, so only its height
  /// and position count.
  func describeDifferences(from other: ChatLayout) -> [String] {
    var differences: [String] = []
    let parts = [("the page", webView, other.webView), ("Back", back, other.back)]
    for (name, frame, otherFrame) in parts where !UsabilityTests.isSameFrame(frame, otherFrame) {
      differences.append(Self.describeMove(name, frame, otherFrame))
    }
    let verticalParts = [("the composer", composer, other.composer), ("the newest message", newest, other.newest)]
    for (name, frame, otherFrame) in verticalParts
      where !UsabilityTests.isSameVerticalPlace(frame, otherFrame) {
      differences.append(Self.describeMove(name, frame, otherFrame))
    }
    return differences
  }

  private static func describeMove(_ name: String, _ frame: CGRect, _ otherFrame: CGRect) -> String {
    "\(name) is at \(UsabilityTests.describe(frame)) instead of \(UsabilityTests.describe(otherFrame))"
  }
}

/// What `Fixtures/ui-probe.js` reports about the page, in CSS pixels, which are points in the app
private struct PageProbe: Decodable {
  struct Offsets: Decodable {
    let scrollTop: CGFloat
    let scrollY: CGFloat
    let pageTop: CGFloat
    let offsetTop: CGFloat
  }

  let scrollTop: CGFloat
  let scrollY: CGFloat
  let pageTop: CGFloat
  let offsetTop: CGFloat
  /// The highest offsets since the page started
  let max: Offsets
  let innerWidth: CGFloat
  let innerHeight: CGFloat
  let clientHeight: CGFloat
  let visualHeight: CGFloat
  let htmlHeight: CGFloat
  /// The web app's `--vh` times 100
  let vh: CGFloat?
  let safeTop: CGFloat
  let safeBottom: CGFloat
  let themeColor: String?
  let theme: String?
  let active: String
  let hasFocus: Bool
  let isInBackground: Bool
  let isKeyboardVisible: Bool
}

/// An sRGB color with 8-bit channels
private struct RGBColor {
  let red: Int
  let green: Int
  let blue: Int

  init(red: Int, green: Int, blue: Int) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  /// `#rgb` or `#rrggbb`, the forms of `<meta name="theme-color">`
  init?(hex: String) {
    var digits = hex.trimmingCharacters(in: .whitespaces)
    guard digits.hasPrefix("#") else {
      return nil
    }
    digits.removeFirst()
    if digits.count == 3 {
      digits = digits.map { "\($0)\($0)" }.joined()
    }
    guard digits.count == 6, let value = Int(digits, radix: 16) else {
      return nil
    }
    red = (value >> 16) & 0xFF
    green = (value >> 8) & 0xFF
    blue = value & 0xFF
  }

  var hex: String {
    "#" + [red, green, blue].map { channel in
      let digits = String(channel, radix: 16)
      return digits.count == 1 ? "0" + digits : digits
    }.joined()
  }

  func isClose(to other: RGBColor, tolerance: Int) -> Bool {
    abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance && abs(blue - other.blue) <= tolerance
  }

  /// The distinct colors in the order they first appear
  static func describe(_ colors: [RGBColor]) -> String {
    var names: [String] = []
    for color in colors where !names.contains(color.hex) {
      names.append(color.hex)
    }
    return names.joined(separator: ", ")
  }
}

/// Pixel colors of a screenshot at points of the screen, read through an sRGB bitmap
private struct ScreenPixels {
  private static let bytesPerPixel = 4
  private static let bitsPerComponent = 8

  private let image: CGImage
  private let scale: CGFloat

  init?(image: CGImage?, pointWidth: CGFloat) {
    guard let image, pointWidth > 0 else {
      return nil
    }
    self.image = image
    scale = CGFloat(image.width) / pointWidth
  }

  /// The colors at the points `xs` of the row at `y`, all in points
  func readColors(atY y: CGFloat, xs: [CGFloat]) -> [RGBColor]? {
    let pixelY = Int((y * scale).rounded(.down))
    guard pixelY >= 0, pixelY < image.height,
          let row = image.cropping(to: CGRect(x: 0, y: pixelY, width: image.width, height: 1)),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      return nil
    }
    let width = row.width
    var bytes = [UInt8](repeating: 0, count: width * Self.bytesPerPixel)
    let isDrawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress,
        width: width,
        height: 1,
        bitsPerComponent: Self.bitsPerComponent,
        bytesPerRow: width * Self.bytesPerPixel,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
        return false
      }
      context.draw(row, in: CGRect(x: 0, y: 0, width: width, height: 1))
      return true
    }
    guard isDrawn else {
      return nil
    }
    return xs.map { x in
      let pixelX = min(max(Int((x * scale).rounded(.down)), 0), width - 1)
      let offset = pixelX * Self.bytesPerPixel
      return RGBColor(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
    }
  }
}
