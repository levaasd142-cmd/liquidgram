import XCTest

/// The record button of a chat works as in Telegram's apps: a tap switches between voice and video messages, holding
/// records, sliding left cancels and sliding up locks the recording. The demo account stays offline, so nothing is
/// sent, and `Fixtures/fake-capture.js` gives the page the microphone and the round video recorder that the CI
/// simulator lacks. The fixture shows how often the page opened the microphone and how many of its tracks are live.
final class RecordingTests: LiquidgramUITestCase {
  private static let captureFixture = "fake-capture"
  private static let demoChatTitle = "Аня Смирнова"
  private static let voiceButtonLabel = "Record voice message"
  private static let videoButtonLabel = "Record video message"
  private static let videoModeHint = "Hold to record video"
  private static let voiceModeHint = "Hold to record audio"
  private static let cancelRecordingLabel = "Cancel voice recording"
  private static let microphoneStatusPrefix = "Test microphone"
  /// Longer than the 0.19 seconds after which a press starts recording, and long enough to record something
  private static let holdDuration: TimeInterval = 1.2
  /// Past the 150 points that cancel and the 110 points that lock while the finger moves
  private static let slideDistance: CGFloat = 200
  /// The button ignores a touch that starts sooner than 0.4 seconds after the one before, as Telegram's does
  private static let betweenTouchesDelay: TimeInterval = 1

  /// A tap switches to video messages and back, shows how the button works and records nothing
  @MainActor
  func testTapSwitchesBetweenVoiceAndVideo() throws {
    let voiceButton = try openDemoChat()
    attachScreenshot("01-voice-mode")

    voiceButton.tap()
    let videoButton = waitForHittable(webView.buttons[Self.videoButtonLabel], "the record button in video mode")
    waitFor(findElement(in: webView, labelContaining: Self.videoModeHint), "the hint that holding records a video")
    attachScreenshot("02-video-mode")
    XCTAssertFalse(
      findStaticText(in: webView, containing: Self.microphoneStatusPrefix).exists,
      "The tap opened the microphone"
    )

    pause(Self.betweenTouchesDelay)
    videoButton.tap()
    waitForHittable(webView.buttons[Self.voiceButtonLabel], "the record button back in voice mode")
    waitFor(findElement(in: webView, labelContaining: Self.voiceModeHint), "the hint that holding records audio")
    attachScreenshot("03-voice-mode-again")
  }

  /// Holding the button records a voice message; sliding left cancels it, sliding up locks it, and the locked
  /// recording keeps its trash button
  @MainActor
  func testHoldRecordsVoiceAndSlidesCancelOrLock() throws {
    let recordButton = try openDemoChat()
    let start = recordButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

    start.press(forDuration: Self.holdDuration, thenDragTo: start.withOffset(CGVector(dx: -Self.slideDistance, dy: 0)))
    waitFor(
      findStaticText(in: webView, containing: microphoneStatus(opened: 1, live: 0)),
      "the microphone that the press opened and the slide to the left closed"
    )
    waitForHittable(webView.buttons[Self.voiceButtonLabel], "the record button after cancelling")
    XCTAssertFalse(webView.buttons[Self.cancelRecordingLabel].exists, "A recording is left after sliding to cancel")
    attachScreenshot("01-cancelled")

    pause(Self.betweenTouchesDelay)
    start.press(forDuration: Self.holdDuration, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -Self.slideDistance)))
    let trashButton = waitForHittable(
      webView.buttons[Self.cancelRecordingLabel],
      "the trash button of the recording that the slide up locked"
    )
    waitFor(
      findStaticText(in: webView, containing: microphoneStatus(opened: 2, live: 1)),
      "the microphone still recording after the finger lifted"
    )
    attachScreenshot("02-locked")

    trashButton.tap()
    waitFor(
      findStaticText(in: webView, containing: microphoneStatus(opened: 2, live: 0)),
      "the microphone closed by the trash button"
    )
    waitForHittable(webView.buttons[Self.voiceButtonLabel], "the record button after the trash button")
    attachScreenshot("03-discarded")
  }

  /// Opens the demo chat and returns its record button in voice mode
  @MainActor
  private func openDemoChat() throws -> XCUIElement {
    try launchApp(Launch(shouldSeedDemoAccount: true, fixtures: [Self.captureFixture]))
    waitForChatRow(titled: Self.demoChatTitle, "the chat list of the demo account").tap()
    allowNotificationsIfAsked()
    return waitForHittable(webView.buttons[Self.voiceButtonLabel], "the record button of the chat")
  }

  private func microphoneStatus(opened: Int, live: Int) -> String {
    "\(Self.microphoneStatusPrefix): opened \(opened), live \(live)"
  }
}
