import Foundation
import os
import UIKit
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "SelfTest")

/// Hooks for the UI tests in `LiquidgramUITests`. They act only in Debug builds, which the tests run on the
/// simulator, and only when a test passes the matching launch argument or environment variable. Release builds
/// compile the same code, so it stays checked, but `isEnabled` turns every hook into a no-op.
enum TestHooks {
  /// Launch argument `-LiquidgramResetState YES`: removes the native settings and all web data before the app loads
  static let resetStateArgument = "LiquidgramResetState"
  /// Launch argument `-LiquidgramFakeAuthentication success|failure|cancel`: the app lock skips Face ID and gets
  /// this outcome instead
  static let fakeAuthenticationArgument = "LiquidgramFakeAuthentication"
  /// Launch argument `-LiquidgramFakeAuthenticationDelay <seconds>`: how long a faked authentication takes. Tests
  /// that look at the lock screen before it opens pass a delay longer than the launch of the app.
  static let fakeAuthenticationDelayArgument = "LiquidgramFakeAuthenticationDelay"
  /// Launch argument `-LiquidgramTestAction <type>`: once the page is ready, the app performs this native action,
  /// such as `openSavedMessages`, the way a home-screen quick action does
  static let testActionArgument = "LiquidgramTestAction"
  /// Launch environment: base64 UTF-8 JavaScript that runs at document start in the main frame, before the app's
  /// own scripts. The tests use it to seed a demo account into `localStorage`.
  static let userScriptEnvironmentKey = "LIQUIDGRAM_TEST_USER_SCRIPT"
  /// Launch environment: base64 UTF-8 body of an async JavaScript function that returns a string. The app runs it
  /// once the page is ready and shows the result as the accessibility value of `selfTestResultIdentifier`. The
  /// function gets `migrationOutcome`, what `LegacyDataMigration` did at this launch, or an empty string.
  static let selfTestEnvironmentKey = "LIQUIDGRAM_TEST_SELFTEST_SCRIPT"
  static let selfTestResultIdentifier = "liquidgram.selftest.result"

  #if DEBUG
  static let isEnabled = true
  #else
  static let isEnabled = false
  #endif

  /// Pages that never report `appReady`, such as the login screens, run the self-test this long after loading
  private static let selfTestFallbackDelay: TimeInterval = 5
  private static let selfTestLabelAlpha: CGFloat = 0.02
  private static let defaultFakeAuthenticationDelay: TimeInterval = 0.3
  private static var hasRunSelfTest = false
  private static var migrationOutcome = ""

  /// `success`, `failure` or `cancel` while a test fakes the authentication of the app lock, otherwise `nil`
  static var fakeAuthenticationOutcome: String? {
    isEnabled ? UserDefaults.standard.string(forKey: fakeAuthenticationArgument) : nil
  }

  /// How long the app lock waits before it reports `fakeAuthenticationOutcome`: 0.3 seconds unless a test asks for
  /// longer, because an XCUITest launch returns only after the app is idle, when a short fake has already finished
  static var fakeAuthenticationDelay: TimeInterval {
    let delay = UserDefaults.standard.double(forKey: fakeAuthenticationDelayArgument)
    return isEnabled && delay > 0 ? delay : defaultFakeAuthenticationDelay
  }

  /// The native action a test asks for, such as `openSavedMessages`, otherwise `nil`
  static var testAction: String? {
    isEnabled ? UserDefaults.standard.string(forKey: testActionArgument) : nil
  }

  private static var isResetRequested: Bool {
    isEnabled && UserDefaults.standard.bool(forKey: resetStateArgument)
  }

  /// Removes the stored native settings. Runs at launch, before any scene reads them; launch arguments still
  /// override them afterwards.
  static func resetNativeSettingsIfRequested() {
    guard isResetRequested, let domain = Bundle.main.bundleIdentifier else {
      return
    }
    UserDefaults.standard.removePersistentDomain(forName: domain)
    logger.notice("Removed the native settings")
  }

  /// Removes all web data when a test asks for a clean start, then calls `completion` on the main queue
  static func prepareForLaunch(completion: @escaping () -> Void) {
    guard isResetRequested else {
      completion()
      return
    }
    let dataStore = WKWebsiteDataStore.default()
    dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
      logger.notice("Removed the web data")
      DispatchQueue.main.async(execute: completion)
    }
  }

  /// User scripts that a test adds in front of the app's own document-start scripts
  static func makeUserScripts() -> [WKUserScript] {
    guard isEnabled, let source = decodeEnvironmentScript(userScriptEnvironmentKey) else {
      return []
    }
    return [WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)]
  }

  /// What the migration of version 1's data did at this launch, for the self-test
  static func recordMigration(_ outcome: String) {
    guard isEnabled else {
      return
    }
    migrationOutcome = outcome
  }

  /// The app's page finished loading. Pages that report `appReady` run the self-test earlier.
  static func pageDidFinishLoading(in webView: WKWebView) {
    guard isEnabled, !hasRunSelfTest, ProcessInfo.processInfo.environment[selfTestEnvironmentKey] != nil else {
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + selfTestFallbackDelay) { [weak webView] in
      guard let webView else {
        return
      }
      runSelfTest(in: webView)
    }
  }

  /// The web app registered its native action handler
  static func pageDidBecomeReady(in webView: WKWebView) {
    runSelfTest(in: webView)
  }

  private static func runSelfTest(in webView: WKWebView) {
    guard isEnabled, !hasRunSelfTest, let script = decodeEnvironmentScript(selfTestEnvironmentKey) else {
      return
    }
    hasRunSelfTest = true
    let arguments = ["migrationOutcome": migrationOutcome]
    webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
      let report: String
      switch result {
      case .success(let value):
        report = value as? String ?? String(describing: value)
      case .failure(let error):
        report = makeErrorReport(error)
      }
      logger.notice("Self-test result: \(report, privacy: .public)")
      showSelfTestResult(report, in: webView.window)
    }
  }

  /// Puts the report where an XCUITest can read it: the accessibility value of a nearly transparent label
  private static func showSelfTestResult(_ report: String, in window: UIWindow?) {
    guard let window else {
      logger.error("No window to show the self-test result in")
      return
    }
    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    label.text = selfTestResultIdentifier
    label.alpha = selfTestLabelAlpha
    label.isAccessibilityElement = true
    label.accessibilityIdentifier = selfTestResultIdentifier
    label.accessibilityValue = report
    window.addSubview(label)
  }

  private static func makeErrorReport(_ error: Error) -> String {
    let report = ["error": error.localizedDescription]
    guard let data = try? JSONSerialization.data(withJSONObject: report),
          let json = String(data: data, encoding: .utf8) else {
      return "{\"error\":\"unknown\"}"
    }
    return json
  }

  private static func decodeEnvironmentScript(_ key: String) -> String? {
    guard let encoded = ProcessInfo.processInfo.environment[key], let data = Data(base64Encoded: encoded) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}
