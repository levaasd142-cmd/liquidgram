import XCTest

/// How the app serves the web app since it left the loopback server: videos and music stream from the page through
/// `liquidgram-web://app/progressive/`, and the data of the loopback version moves into the app's origin.
final class TransportTests: LiquidgramUITestCase {
  /// The stream check plays media with delays that stand for the network
  private static let streamCheckTimeout: TimeInterval = 180
  private static let migrationCheckTimeout: TimeInterval = 90
  /// The app removes the old origin's data 10 seconds after its start
  private static let legacyDataRemovalTimeout: TimeInterval = 40
  private static let legacyDataRemovedIdentifier = "liquidgram.migration.legacyDataRemoved"
  /// `run-ui-tests.sh` sets `TEST_RUNNER_LIQUIDGRAM_LEGACY_SEEDED=1` once the loopback version ran with the demo account
  private static let legacySeededEnvironmentKey = "LIQUIDGRAM_LEGACY_SEEDED"
  private static let scriptSeparator = "\n;\n"
  private static let demoChatTitle = "Аня Смирнова"

  /// `Fixtures/stream-check.js` streams a video through the web app's own part loader, then checks ranges, failures,
  /// music that starts before it is downloaded and seeking with a synthetic part loader
  @MainActor
  func testMediaStreamsFromPage() throws {
    try launchWithScripts(
      userScripts: ["page-errors", "media-api", "demo-account"],
      selfTest: "stream-check",
      shouldResetState: true
    )
    waitForChatRow(titled: Self.demoChatTitle, "the chat list of the demo account")
    let result = waitFor(
      findNativeElement(Self.selfTestResultIdentifier),
      timeout: Self.streamCheckTimeout,
      "the report of the stream check"
    )
    attachScreenshot("01-stream-check-finished")
    try assertChecksPassed(result, reportName: "selftest-report-stream")
  }

  /// After the loopback version of the app ran with the demo account and `Fixtures/legacy-seed.js`, this version
  /// starts over its data: the session, the API keys, the cached chats and the seeded values are in the app's origin,
  /// and the old origin's data is removed afterwards
  @MainActor
  func testLegacyDataMovesToAppOrigin() throws {
    guard ProcessInfo.processInfo.environment[Self.legacySeededEnvironmentKey] == "1" else {
      throw XCTSkip("Needs the data of the loopback version; run-ui-tests.sh seeds it with UI_TESTS_LEGACY_REF")
    }
    try launchWithScripts(userScripts: ["page-errors", "offline-api"], selfTest: "migration-check", shouldResetState: false)
    waitForChatRow(titled: Self.demoChatTitle, "the chats of the demo account after the migration")
    attachScreenshot("01-chats-after-migration")
    let result = waitFor(
      findNativeElement(Self.selfTestResultIdentifier),
      timeout: Self.migrationCheckTimeout,
      "the report of the migration check"
    )
    try assertChecksPassed(result, reportName: "selftest-report-migration")
    waitFor(
      findNativeElement(Self.legacyDataRemovedIdentifier),
      timeout: Self.legacyDataRemovalTimeout,
      "the removal of the loopback version's data"
    )
  }

  /// Launches the app with fixtures as document-start scripts and another self-test than `selftest.js`
  @MainActor
  private func launchWithScripts(userScripts: [String], selfTest: String, shouldResetState: Bool) throws {
    let app = XCUIApplication()
    var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    if shouldResetState {
      arguments += ["-LiquidgramResetState", "YES"]
    }
    app.launchArguments = arguments
    let scripts = try userScripts.map { try loadFixture($0) }
    app.launchEnvironment[Self.userScriptEnvironmentKey] = Self.encodeScript(scripts.joined(separator: Self.scriptSeparator))
    app.launchEnvironment[Self.selfTestEnvironmentKey] = Self.encodeScript(try loadFixture(selfTest))
    app.launch()
  }

  @MainActor
  private func assertChecksPassed(_ result: XCUIElement, reportName: String) throws {
    let report = try XCTUnwrap(result.value as? String, "The check has no report")
    attachJSON(report, name: reportName)
    let decodedReport = try JSONDecoder().decode(CheckReport.self, from: Data(report.utf8))
    if let error = decodedReport.error {
      XCTFail("The check script failed: \(error)")
    }
    let checks = decodedReport.checks ?? []
    XCTAssertFalse(checks.isEmpty, "The report has no checks")
    let failedChecks = checks.filter { !$0.ok }
    XCTAssertTrue(
      failedChecks.isEmpty,
      "Failed checks: " + failedChecks.map { "\($0.name) (\($0.detail ?? ""))" }.joined(separator: "; ")
    )
  }

  private static func encodeScript(_ source: String) -> String {
    Data(source.utf8).base64EncodedString()
  }
}

/// The JSON of the check scripts, or the error report of `TestHooks` when a script throws
private struct CheckReport: Decodable {
  struct Check: Decodable {
    let name: String
    let ok: Bool
    let detail: String?
  }

  let checks: [Check]?
  let error: String?
}
