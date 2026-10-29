import XCTest

/// Gestures of the web app that work as in Telegram for iPhone: the swipe back from a chat to the chat list, from the
/// screen edge or from the middle, which springs back when it is short and slow; the swipe back from a profile; the
/// chat list, which has nothing to go back to; the long press on a message, whose menu takes the next tap; and the
/// swipe to reply. The swipes run through the touch events of the web view, as a finger's do.
final class GestureTests: LiquidgramUITestCase {
  private static let demoChatTitle = "Аня Смирнова"
  /// A chat of the list other than the opened one, so finding it on screen tells that the chat list is back
  private static let otherChatTitle = "Бразы"
  /// An incoming and an outgoing message of the demo chat in `Fixtures/demo-account.js`
  private static let incomingMessage = "Во сколько завтра встречаемся?"
  private static let outgoingMessage = "Давай в 19:00 у кофейни"
  private static let composerLabel = "Message"
  private static let menuButtonLabel = "Open menu"
  private static let replyMenuItemLabel = "Reply"
  /// The button that cancels the reply above the composer
  private static let cancelReplyLabel = "Cancel"
  /// A row of the profile of the demo chat
  private static let profileRowLabel = "Notifications"
  /// Tabs of the global search, which the chat list must not open on a right swipe
  private static let searchTabLabels = ["Channels", "Media"]
  /// Within the 20 points from the left edge where the web app starts its edge swipes
  private static let edgeInset: CGFloat = 4
  /// Where the swipes of a chat run: the middle of its messages, between the header and the composer
  private static let chatSwipeY: CGFloat = 0.5
  /// Where the swipe of a profile runs: below its photo, over its rows and shared media
  private static let profileSwipeY: CGFloat = 0.75
  private static let swipeEndX: CGFloat = 0.85
  private static let middleSwipeStartX: CGFloat = 0.3
  /// A quarter of the width, short of the 40 percent that a release without speed needs
  private static let shortSwipeEndX: CGFloat = 0.25
  private static let chatListSwipeStartX: CGFloat = 0.15
  private static let pressBeforeDrag: TimeInterval = 0.05
  /// Points per second: a quick swipe, and a slow one that rests before the finger lifts, so it has no speed
  private static let quickSwipeVelocity = XCUIGestureVelocity(rawValue: 1200)
  private static let slowSwipeVelocity = XCUIGestureVelocity(rawValue: 150)
  private static let replySwipeVelocity = XCUIGestureVelocity(rawValue: 400)
  private static let restBeforeLift: TimeInterval = 0.6
  /// Past the 56 points at which a swipe on a message replies
  private static let replySwipeDistance: CGFloat = 140
  /// Longer than the 0.4 seconds of the web app's long press
  private static let longPressDuration: TimeInterval = 1
  /// A swipe settles within 0.3 seconds, and the layout follows within a few frames
  private static let settleDelay: TimeInterval = 1.5

  /// A quick swipe from the left edge of a chat goes back to the chat list
  @MainActor
  func testSwipeBackFromEdgeClosesChat() throws {
    try openDemoChat()
    swipe(
      from: edgePoint(y: Self.chatSwipeY),
      to: point(x: Self.swipeEndX, y: Self.chatSwipeY),
      velocity: Self.quickSwipeVelocity
    )
    waitForChatList("the chat list after a swipe back from the left edge")
    attachScreenshot("02-chat-list-after-edge-swipe")
  }

  /// A swipe back starts anywhere in a chat, not only at the edge
  @MainActor
  func testSwipeBackFromMiddleClosesChat() throws {
    try openDemoChat()
    swipe(
      from: point(x: Self.middleSwipeStartX, y: Self.chatSwipeY),
      to: point(x: Self.swipeEndX, y: Self.chatSwipeY),
      velocity: Self.quickSwipeVelocity
    )
    waitForChatList("the chat list after a swipe back from the middle")
    attachScreenshot("02-chat-list-after-middle-swipe")
  }

  /// A short swipe back that stops before the finger lifts springs back, and the chat stays
  @MainActor
  func testSlowShortSwipeSpringsBack() throws {
    let composer = try openDemoChat()
    swipe(
      from: edgePoint(y: Self.chatSwipeY),
      to: point(x: Self.shortSwipeEndX, y: Self.chatSwipeY),
      velocity: Self.slowSwipeVelocity,
      restBeforeLift: Self.restBeforeLift
    )
    pause(Self.settleDelay)
    attachScreenshot("02-chat-after-short-swipe")
    XCTAssertTrue(isOnScreen(composer), "The chat closed after a short and slow swipe")
    XCTAssertFalse(isOnScreen(menuButton), "The chat list is on screen after a short and slow swipe")
    // WebKit clicks when a finger that rested lifts, which must not open a chat that the swipe uncovered
    XCTAssertTrue(
      isOnScreen(webView.staticTexts.matching(Self.makeLabelPredicate(containing: Self.incomingMessage)).firstMatch),
      "Another chat opened after a short and slow swipe"
    )
  }

  /// A quick swipe from the left edge of a profile goes back to its chat
  @MainActor
  func testSwipeBackClosesProfile() throws {
    let composer = try openDemoChat()
    let title = waitForHittable(
      webView.buttons.matching(NSPredicate(format: "label == %@", Self.demoChatTitle)),
      "the title in the header of the chat"
    )
    try XCTSkipIf(
      title.frame.midY < statusBarFrame.maxY,
      "The chat header is under the status bar, which takes the tap that opens the profile"
    )
    title.tap()
    waitForHittable(findElements(in: webView, labelContaining: Self.profileRowLabel), "a row of the profile")
    attachScreenshot("02-profile")

    swipe(
      from: edgePoint(y: Self.profileSwipeY),
      to: point(x: Self.swipeEndX, y: Self.profileSwipeY),
      velocity: Self.quickSwipeVelocity
    )
    // The profile covers the composer until it closes
    waitForHittable(composer, "the composer of the chat after a swipe back from the profile")
    attachScreenshot("03-chat-after-profile-swipe")
  }

  /// A right swipe on the chat list, which has nothing to go back to, leaves it as it is instead of opening the search
  @MainActor
  func testChatListRightSwipeKeepsChatList() throws {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list of the demo account")
    waitForHittable(menuButton, "the menu button of the chat list")
    attachScreenshot("01-chat-list")

    swipe(
      from: point(x: Self.chatListSwipeStartX, y: Self.chatSwipeY),
      to: point(x: Self.swipeEndX, y: Self.chatSwipeY),
      velocity: Self.quickSwipeVelocity
    )
    pause(Self.settleDelay)
    attachScreenshot("02-chat-list-after-right-swipe")

    XCTAssertTrue(isOnScreen(menuButton), "The menu button of the chat list is gone, so another screen opened")
    let searchTabs = webView.descendants(matching: .any)
      .matching(NSPredicate(format: "label IN %@", Self.searchTabLabels as NSArray))
      .allElementsBoundByIndex.filter { isOnScreen($0) }
    XCTAssertTrue(
      searchTabs.isEmpty,
      "The right swipe opened the search: " + searchTabs.map(\.label).joined(separator: ", ")
    )
    XCTAssertFalse(keyboard.exists, "The right swipe brought up the keyboard")
  }

  /// A long press on a message opens its menu without selecting text, and the first tap on an item does what the item
  /// says
  @MainActor
  func testLongPressOpensMessageMenu() throws {
    try openDemoChat()
    let message = waitForHittable(
      webView.staticTexts.matching(Self.makeLabelPredicate(containing: Self.incomingMessage)),
      "the incoming message"
    )
    message.press(forDuration: Self.longPressDuration)
    // A selected text turns the item into Quote & Reply
    let replyItem = waitForHittable(
      webView.descendants(matching: .any).matching(NSPredicate(format: "label ENDSWITH %@", Self.replyMenuItemLabel)),
      "the reply item of the message menu"
    )
    let replyItemLabel = replyItem.label
    attachScreenshot("02-message-menu")
    attachAccessibilityTree("message-menu")

    replyItem.tap()
    waitForHittable(cancelReplyButtons, "the reply above the composer after a tap on the reply item")
    attachScreenshot("03-reply-from-menu")
    XCTAssertEqual(replyItemLabel, Self.replyMenuItemLabel, "The long press selected text of the message")
  }

  /// A message swiped to the left past the threshold becomes the reply of the composer
  @MainActor
  func testSwipeToReply() throws {
    try openDemoChat()
    let message = waitForHittable(
      webView.staticTexts.matching(Self.makeLabelPredicate(containing: Self.outgoingMessage)),
      "the outgoing message"
    )
    XCTAssertFalse(
      cancelReplyButtons.allElementsBoundByIndex.contains { isOnScreen($0) },
      "The composer has a reply before the swipe"
    )

    let start = message.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    swipe(
      from: start,
      to: start.withOffset(CGVector(dx: -Self.replySwipeDistance, dy: 0)),
      velocity: Self.replySwipeVelocity
    )
    waitForHittable(cancelReplyButtons, "the reply above the composer after a swipe to the left")
    attachScreenshot("02-reply-from-swipe")
  }

  // MARK: - Helpers

  /// Starts the app with the demo account and opens its private chat; returns the composer
  @MainActor
  @discardableResult
  private func openDemoChat() throws -> XCUIElement {
    try launchApp(Launch(shouldSeedDemoAccount: true))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list of the demo account").tap()
    allowNotificationsIfAsked()
    let composer = waitForHittable(findTextInput(in: webView, labeled: Self.composerLabel), "the composer of the chat")
    // The chat slides in after the tap
    pause(Self.settleDelay)
    attachScreenshot("01-chat")
    return composer
  }

  /// The menu button in the header of the chat list
  @MainActor
  private var menuButton: XCUIElement {
    webView.buttons[Self.menuButtonLabel]
  }

  @MainActor
  private var cancelReplyButtons: XCUIElementQuery {
    webView.buttons.matching(NSPredicate(format: "label == %@", Self.cancelReplyLabel))
  }

  /// Waits until the chat list is on screen: another chat of the list, and the menu button of its header
  @MainActor
  private func waitForChatList(_ description: String) {
    waitForChatRow(titled: Self.otherChatTitle, timeout: Self.elementTimeout, description)
    waitForHittable(menuButton, description)
  }

  /// Web content keeps screens that slid away in the accessibility tree, so only a hittable element is on screen. An
  /// element without a frame on screen is not asked, as XCUITest fails the test when it finds no point to hit.
  @MainActor
  private func isOnScreen(_ element: XCUIElement) -> Bool {
    guard element.exists else {
      return false
    }
    let frame = element.frame
    return !frame.isEmpty && app.frame.intersects(frame) && element.isHittable
  }

  /// A point of the web view at shares of its width and height
  @MainActor
  private func point(x: CGFloat, y: CGFloat) -> XCUICoordinate {
    webView.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
  }

  /// A point at the left edge of the web view, at a share of its height
  @MainActor
  private func edgePoint(y: CGFloat) -> XCUICoordinate {
    point(x: 0, y: y).withOffset(CGVector(dx: Self.edgeInset, dy: 0))
  }

  /// A finger that touches `start`, moves to `end` at `velocity` and lifts after `restBeforeLift`
  @MainActor
  private func swipe(
    from start: XCUICoordinate,
    to end: XCUICoordinate,
    velocity: XCUIGestureVelocity,
    restBeforeLift: TimeInterval = 0
  ) {
    start.press(
      forDuration: Self.pressBeforeDrag,
      thenDragTo: end,
      withVelocity: velocity,
      thenHoldForDuration: restBeforeLift
    )
  }
}
