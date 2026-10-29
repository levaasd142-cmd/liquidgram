import XCTest

/// The native round video recorder (кружки). `Fixtures/round-video.js` opens it from the page through the bridge, as
/// the composer does, and reports what the page received; the test drives the recorder on screen. The simulator has
/// no camera, so `-LiquidgramFakeRoundVideo YES` gives the recorder generated frames and silence, and the app reports
/// what the recorded file holds as `liquidgram.roundVideo.testReport`. The checks become a table in the report.
final class RoundVideoTests: LiquidgramUITestCase {
  private static let fakeRoundVideoArgument = "-LiquidgramFakeRoundVideo"
  private static let selfTestFixture = "round-video"
  private static let errorRecorderFixture = "page-errors"
  private static let recorderIdentifier = "liquidgram.roundVideo.recorder"
  private static let sendIdentifier = "liquidgram.roundVideo.send"
  private static let cancelIdentifier = "liquidgram.roundVideo.cancel"
  private static let flipIdentifier = "liquidgram.roundVideo.flip"
  private static let flashIdentifier = "liquidgram.roundVideo.flash"
  private static let viewOnceIdentifier = "liquidgram.roundVideo.viewOnce"
  private static let timerIdentifier = "liquidgram.roundVideo.timer"
  private static let messageIdentifier = "liquidgram.roundVideo.message"
  private static let closeIdentifier = "liquidgram.roundVideo.close"
  private static let reportIdentifier = "liquidgram.roundVideo.testReport"
  private static let noCameraTitle = "No camera"
  /// The scheme of `AppSchemeHandler`; only it serves the recordings to the page
  private static let appSchemePrefix = "liquidgram-web:"
  private static let mediaPathPattern = "^/__liquidgram/media/[0-9a-f]{32}\\.mp4$"
  /// The self-test starts 5 seconds after the first page load of a clean start
  private static let recorderTimeout: TimeInterval = 60
  private static let recordingStartTimeout: TimeInterval = 15
  private static let resultTimeout: TimeInterval = 30
  private static let recordingDuration: TimeInterval = 2
  private static let dimension = 480
  private static let profileHigh = 100
  private static let aacLowComplexity = 2
  private static let sampleRate = 48_000
  private static let minimumDurationMs = 1000
  private static let durationToleranceMs = 150
  /// At least this many frames per second of video, below the 30 that the generated camera delivers
  private static let minimumFrameRate = 15
  /// Bytes per second the file may take at most: 1 Mbit/s of video and 64 kbit/s of sound, with room for the boxes
  private static let maximumBytesPerSecond = 250_000

  // MARK: - Tests

  /// Records with the generated camera, switches the flash, the camera and view-once on the way, sends, and checks the
  /// file: a square 480 px H.264 High profile video with CABAC and mono 48 kHz AAC in an MP4 that starts with its movie
  /// header, of the duration the page got. The page gets the path and the details, and the file is gone once the page
  /// released it.
  @MainActor
  func testRecordsAndSendsRoundVideo() throws {
    try launchRecorderTest(shouldFakeCamera: true)
    let recorder = waitFor(
      findNativeElement(Self.recorderIdentifier),
      timeout: Self.recorderTimeout,
      "the round video recorder that the page opened"
    )
    let send = waitFor(findNativeElement(Self.sendIdentifier), "the send button")
    XCTAssertTrue(
      waitUntil(timeout: Self.recordingStartTimeout) { send.isEnabled },
      "Send stays disabled, so the recording did not start or stays under a second"
    )
    attachScreenshot("01-recording")

    waitForHittable(findNativeElement(Self.flashIdentifier), "the flash button").tap()
    pause(Self.recordingDuration / 2)
    attachScreenshot("02-screen-flash")
    waitForHittable(findNativeElement(Self.flipIdentifier), "the switch camera button").tap()
    waitForHittable(findNativeElement(Self.viewOnceIdentifier), "the view-once button").tap()
    pause(Self.recordingDuration)
    attachScreenshot("03-back-camera-view-once")
    attachAccessibilityTree("recorder")

    send.tap()
    waitForDisappearance(of: recorder, "the recorder after Send")
    let page = try readPageReport()
    let report = try readNativeReport(untilEvent: "released")
    attachScreenshot("04-after-send")

    var checks = checkPageResult(page, isViewOnce: true)
    checks += checkFile(report, page: page)
    checks += checkPageFetch(page, report: report)
    let events = report["events"] as? [String] ?? []
    checks.append(Check(
      name: "roundVideoEvents",
      isOK: events == ["presented", "sent", "released"],
      detail: events.joined(separator: ", ")
    ))
    checks.append(Check(
      name: "roundVideoReleased",
      isOK: report["storedFiles"] as? Int == 0,
      detail: "\(report["storedFiles"] ?? "nil") files stored after the release"
    ))
    try assertChecks(checks, page: page, report: report)
  }

  /// Cancel discards the recording: the page gets `null` and no file stays
  @MainActor
  func testCancelDiscardsRecording() throws {
    try launchRecorderTest(shouldFakeCamera: true)
    let recorder = waitFor(
      findNativeElement(Self.recorderIdentifier),
      timeout: Self.recorderTimeout,
      "the round video recorder that the page opened"
    )
    let send = waitFor(findNativeElement(Self.sendIdentifier), "the send button")
    XCTAssertTrue(waitUntil(timeout: Self.recordingStartTimeout) { send.isEnabled }, "The recording did not start")
    attachScreenshot("01-recording")

    waitForHittable(findNativeElement(Self.cancelIdentifier), "the cancel button").tap()
    waitForDisappearance(of: recorder, "the recorder after Cancel")
    let page = try readPageReport()
    let report = try readNativeReport(untilEvent: "cancelled")
    attachScreenshot("02-after-cancel")

    let events = report["events"] as? [String] ?? []
    try assertChecks([
      Check(name: "roundVideoCancelResult", isOK: page["result"] is NSNull, detail: describe(page["result"])),
      Check(
        name: "roundVideoCancelEvents",
        isOK: events == ["presented", "cancelled"],
        detail: events.joined(separator: ", ")
      ),
      Check(
        name: "roundVideoCancelFiles",
        isOK: report["storedFiles"] as? Int == 0,
        detail: "\(report["storedFiles"] ?? "nil") files stored"
      ),
    ], page: page, report: report)
  }

  /// Without a camera, as on the simulator, the recorder says so, and closing it gives the page `null`
  @MainActor
  func testRecorderExplainsMissingCamera() throws {
    try launchRecorderTest(shouldFakeCamera: false)
    let recorder = waitFor(
      findNativeElement(Self.recorderIdentifier),
      timeout: Self.recorderTimeout,
      "the round video recorder that the page opened"
    )
    waitFor(findNativeElement(Self.messageIdentifier), "the message of the recorder")
    waitFor(app.staticTexts[Self.noCameraTitle], "the no camera title")
    attachScreenshot("01-no-camera")

    waitForHittable(findNativeElement(Self.closeIdentifier), "the close button").tap()
    waitForDisappearance(of: recorder, "the recorder after Close")
    let page = try readPageReport()
    try assertChecks([
      Check(name: "roundVideoNoCameraResult", isOK: page["result"] is NSNull, detail: describe(page["result"])),
    ], page: page, report: [:])
  }

  // MARK: - Launch and reports

  private struct Check {
    let name: String
    let isOK: Bool
    let detail: String
  }

  private static func encodeScript(_ source: String) -> String {
    Data(source.utf8).base64EncodedString()
  }

  private static func readJSONObject(_ json: String, _ description: String) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
    return try XCTUnwrap(object as? [String: Any], "\(description) is not a JSON object: \(json)")
  }

  /// A clean start on the API keys screen, where the self-test of `round-video.js` runs 5 seconds after the page loads
  @MainActor
  private func launchRecorderTest(shouldFakeCamera: Bool) throws {
    let app = self.app
    var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-LiquidgramResetState", "YES"]
    if shouldFakeCamera {
      arguments += [Self.fakeRoundVideoArgument, "YES"]
    }
    app.launchArguments = arguments
    app.launchEnvironment[Self.userScriptEnvironmentKey] = Self.encodeScript(try loadFixture(Self.errorRecorderFixture))
    app.launchEnvironment[Self.selfTestEnvironmentKey] = Self.encodeScript(try loadFixture(Self.selfTestFixture))
    app.launch()
  }

  /// What the page received, from the self-test
  @MainActor
  private func readPageReport() throws -> [String: Any] {
    let result = waitFor(
      findNativeElement(Self.selfTestResultIdentifier),
      timeout: Self.resultTimeout,
      "the page's report"
    )
    let json = try XCTUnwrap(result.value as? String, "The page's report is empty")
    attachJSON(json, name: "round-video-page")
    return try Self.readJSONObject(json, "The page's report")
  }

  /// What the app did, once its report has `event`
  @MainActor
  private func readNativeReport(untilEvent event: String) throws -> [String: Any] {
    let element = waitFor(findNativeElement(Self.reportIdentifier), timeout: Self.resultTimeout, "the app's report")
    let hasEvent = waitUntil(timeout: Self.resultTimeout) {
      (element.value as? String)?.contains("\"\(event)\"") == true
    }
    let json = try XCTUnwrap(element.value as? String, "The app's report is empty")
    attachJSON(json, name: "round-video-app")
    XCTAssertTrue(hasEvent, "The app's report has no \(event) event: \(json)")
    return try Self.readJSONObject(json, "The app's report")
  }

  /// Attaches the checks as a self-test table for the report, then fails with the failed ones
  private func assertChecks(_ checks: [Check], page: [String: Any], report: [String: Any]) throws {
    let table: [String: Any] = [
      "ok": checks.allSatisfy(\.isOK),
      "checks": checks.map { ["name": $0.name, "ok": $0.isOK, "detail": $0.detail] },
      "info": ["page": page, "app": report],
    ]
    let data = try JSONSerialization.data(withJSONObject: table, options: [.sortedKeys])
    attachJSON(String(decoding: data, as: UTF8.self), name: "selftest-report-round-video")
    let failedChecks = checks.filter { !$0.isOK }
    XCTAssertTrue(
      failedChecks.isEmpty,
      "Failed round video checks: " + failedChecks.map { "\($0.name) (\($0.detail))" }.joined(separator: "; ")
    )
  }

  // MARK: - Checks

  private func checkPageResult(_ page: [String: Any], isViewOnce: Bool) -> [Check] {
    let result = page["result"] as? [String: Any] ?? [:]
    let url = result["url"] as? String ?? ""
    let isMediaPath = url.range(of: Self.mediaPathPattern, options: .regularExpression) != nil
    let durationMs = result["durationMs"] as? Int ?? 0
    let width = result["width"] as? Int
    let height = result["height"] as? Int
    return [
      Check(
        name: "roundVideoBridge",
        isOK: page["hasRecorder"] as? Bool == true,
        detail: page["origin"] as? String ?? ""
      ),
      Check(
        name: "roundVideoSecondRequest",
        isOK: page["secondRequest"] is NSNull,
        detail: "a second request while recording got \(describe(page["secondRequest"]))"
      ),
      Check(name: "roundVideoPath", isOK: isMediaPath, detail: url),
      Check(
        name: "roundVideoSize",
        isOK: width == Self.dimension && height == Self.dimension,
        detail: "\(width ?? 0)x\(height ?? 0)"
      ),
      Check(
        name: "roundVideoResultDuration",
        isOK: durationMs >= Self.minimumDurationMs,
        detail: "\(durationMs) ms"
      ),
      Check(
        name: "roundVideoViewOnce",
        isOK: result["isViewOnce"] as? Bool == isViewOnce,
        detail: describeFlag(result["isViewOnce"])
      ),
      Check(
        name: "roundVideoPageErrors",
        isOK: (page["pageErrors"] as? [Any])?.isEmpty == true,
        detail: describe(page["pageErrors"])
      ),
    ]
  }

  /// What the app read from the file before the page got it
  private func checkFile(_ report: [String: Any], page: [String: Any]) -> [Check] {
    let file = report["file"] as? [String: Any] ?? [:]
    let tracks = file["tracks"] as? [[String: Any]] ?? []
    let video = tracks.first { $0["handler"] as? String == "vide" } ?? [:]
    let audio = tracks.first { $0["handler"] as? String == "soun" } ?? [:]
    let boxes = file["topLevelBoxes"] as? [String] ?? []
    let size = file["size"] as? Int ?? 0
    let durationMs = file["durationMs"] as? Int ?? 0
    let pageDurationMs = (page["result"] as? [String: Any])?["durationMs"] as? Int ?? 0
    let seconds = Double(durationMs) / 1000
    let frames = video["samples"] as? Int ?? 0

    return [
      Check(
        name: "roundVideoFastStart",
        isOK: file["fastStart"] as? Bool == true && boxes.first == "ftyp",
        detail: boxes.joined(separator: ", ")
      ),
      Check(
        name: "roundVideoVideoTrack",
        isOK: video["codec"] as? String == "avc1" && video["width"] as? Int == Self.dimension
          && video["height"] as? Int == Self.dimension,
        detail: "\(describe(video["codec"])) \(describe(video["width"]))x\(describe(video["height"]))"
      ),
      Check(
        name: "roundVideoH264High",
        isOK: video["profile"] as? Int == Self.profileHigh && video["cabac"] as? Bool == true,
        detail: "profile \(describe(video["profile"])), level \(describe(video["level"])), "
          + "CABAC \(describeFlag(video["cabac"]))"
      ),
      // Decoders read the channels from the AAC configuration; AVAssetWriter puts 2 in the sample entry
      Check(
        name: "roundVideoAudioTrack",
        isOK: audio["codec"] as? String == "mp4a" && audio["audioObjectType"] as? Int == Self.aacLowComplexity
          && audio["sampleRate"] as? Int == Self.sampleRate && audio["channelConfiguration"] as? Int == 1,
        detail: "\(describe(audio["codec"])) object type \(describe(audio["audioObjectType"])), "
          + "\(describe(audio["sampleRate"])) Hz, \(describe(audio["channelConfiguration"])) channel, "
          + "\(describe(audio["averageBitRate"])) bit/s"
      ),
      Check(
        name: "roundVideoDuration",
        isOK: durationMs >= Self.minimumDurationMs && abs(durationMs - pageDurationMs) <= Self.durationToleranceMs,
        detail: "file \(durationMs) ms, page \(pageDurationMs) ms, recorded \(describe(file["recordedDurationMs"])) ms"
      ),
      Check(
        name: "roundVideoFrames",
        isOK: Double(frames) >= seconds * Double(Self.minimumFrameRate),
        detail: "\(frames) frames in \(seconds) s"
      ),
      Check(
        name: "roundVideoFileSize",
        isOK: size > 0 && Double(size) <= max(1, seconds) * Double(Self.maximumBytesPerSecond),
        detail: "\(size) bytes"
      ),
      Check(
        name: "roundVideoDecodes",
        isOK: file["decodedFrame"] as? String == "\(Self.dimension)x\(Self.dimension)",
        detail: describe(file["decodedFrame"])
      ),
    ]
  }

  /// The page fetches the recording only from `AppSchemeHandler`; another server, such as the loopback one of
  /// earlier builds, does not have the media route
  private func checkPageFetch(_ page: [String: Any], report: [String: Any]) -> [Check] {
    let origin = page["origin"] as? String ?? ""
    guard origin.hasPrefix(Self.appSchemePrefix) else {
      return [Check(
        name: "roundVideoPageFetch",
        isOK: true,
        detail: "skipped: \(origin) is not served by AppSchemeHandler, fetch gave \(describe(page["fetch"]))"
      )]
    }
    let fetch = page["fetch"] as? [String: Any] ?? [:]
    let video = fetch["video"] as? [String: Any] ?? [:]
    let range = page["range"] as? [String: Any] ?? [:]
    let afterRelease = page["afterRelease"] as? [String: Any] ?? [:]
    let fileSize = (report["file"] as? [String: Any])?["size"] as? Int
    return [
      Check(
        name: "roundVideoPageFetch",
        isOK: fetch["status"] as? Int == 200 && fetch["blobType"] as? String == "video/mp4"
          && fetch["size"] as? Int == fileSize,
        detail: describe(fetch)
      ),
      Check(
        name: "roundVideoPageDecode",
        isOK: video["width"] as? Int == Self.dimension && video["height"] as? Int == Self.dimension,
        detail: describe(video)
      ),
      Check(
        name: "roundVideoPageRange",
        isOK: range["status"] as? Int == 206 && range["length"] as? Int == 2
          && (range["contentRange"] as? String)?.hasPrefix("bytes 0-1/") == true,
        detail: describe(range)
      ),
      Check(name: "roundVideoPageRelease", isOK: afterRelease["status"] as? Int == 404, detail: describe(afterRelease)),
    ]
  }

  /// `true` or `false` for a JSON boolean, which arrives as a number
  private func describeFlag(_ value: Any?) -> String {
    guard let flag = value as? Bool else {
      return describe(value)
    }
    return flag ? "true" : "false"
  }

  private func describe(_ value: Any?) -> String {
    guard let value else {
      return "missing"
    }
    if value is NSNull {
      return "null"
    }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) {
      return String(decoding: data, as: UTF8.self)
    }
    return String(describing: value)
  }
}
