import Foundation
import os
import UIKit
import UserNotifications
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "NativeBridge")

/// The `Notification.permission` value that matches the system authorization
enum NotificationPermission: String {
  case granted
  case denied
  case notDetermined = "default"

  init(_ status: UNAuthorizationStatus) {
    switch status {
    case .authorized, .provisional, .ephemeral:
      self = .granted
    case .denied:
      self = .denied
    case .notDetermined:
      self = .notDetermined
    @unknown default:
      self = .notDetermined
    }
  }
}

/// Native side of the contract with `Resources/bridge.js`. Two user scripts run at document start in the main
/// frame: one sets `window.__liquidgramNative` and the other is `bridge.js`, which replaces `window.Notification`.
/// The page posts messages to the `liquidgram` handler, and the bridge answers through
/// `window.__liquidgramNative.resolvePermission`, `notificationClicked` and `setPermission`.
/// The app delegate creates the bridge at launch, so it can receive taps on notifications from the start.
/// All state is used on the main queue.
final class NativeBridge: NSObject {
  static let messageHandlerName = "liquidgram"

  private static let bridgeScriptName = "bridge"
  private static let bridgeScriptExtension = "js"
  private static let notificationOptions: UNAuthorizationOptions = [.alert, .sound, .badge]

  weak var webView: WKWebView?
  private weak var userContentController: WKUserContentController?
  private var permission = NotificationPermission.notDetermined
  private let appVersion: String
  private let bridgeScript: String?

  override init() {
    appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    bridgeScript = Self.loadBridgeScript()
    super.init()
  }

  /// Adds the message handler and the user scripts. `WKUserContentController` retains its handlers, so it
  /// gets a weak proxy instead of the bridge.
  func register(in userContentController: WKUserContentController) {
    userContentController.add(WeakScriptMessageHandler(target: self), name: Self.messageHandlerName)
    self.userContentController = userContentController
    installUserScripts()
  }

  /// Reads the authorization, which the user may have changed in Settings, updates the injected state, tells
  /// the page and then calls `completion` on the main queue
  func refreshPermission(completion: (() -> Void)? = nil) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let permission = NotificationPermission(settings.authorizationStatus)
      DispatchQueue.main.async {
        self.applyPermission(permission)
        completion?()
      }
    }
  }

  private static func loadBridgeScript() -> String? {
    guard let url = Bundle.main.url(forResource: bridgeScriptName, withExtension: bridgeScriptExtension),
          let script = try? String(contentsOf: url, encoding: .utf8) else {
      logger.error("bridge.js is missing from the app bundle")
      return nil
    }
    return script
  }

  /// Encodes `value` as a JavaScript string literal
  private static func makeJavaScriptString(_ value: String) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: [value]),
          let arrayLiteral = String(data: data, encoding: .utf8) else {
      return "''"
    }
    // JSON of a one-element array: strip the brackets
    return String(arrayLiteral.dropFirst().dropLast())
  }

  /// The injected state is fixed when a page starts, so the scripts are rebuilt whenever the permission
  /// changes and every later load, such as a reload after the web process ends, gets the current value
  private func installUserScripts() {
    guard let userContentController else {
      return
    }
    userContentController.removeAllUserScripts()

    let environmentScript = "window.__liquidgramNative = { platform: 'ios', "
      + "version: \(Self.makeJavaScriptString(appVersion)), "
      + "notificationPermission: '\(permission.rawValue)' };"
    userContentController.addUserScript(
      WKUserScript(source: environmentScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    )
    if let bridgeScript {
      userContentController.addUserScript(
        WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
      )
    }
  }

  private func applyPermission(_ newPermission: NotificationPermission) {
    if newPermission != permission {
      permission = newPermission
      installUserScripts()
    }
    callPage("setPermission?.('\(permission.rawValue)')")
  }

  private func requestPermission(requestId: Double) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: Self.notificationOptions) { _, error in
      if let error {
        logger.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
      }
      // Read the resulting status rather than the result, which is false for an earlier denial as well
      center.getNotificationSettings { settings in
        let permission = NotificationPermission(settings.authorizationStatus)
        DispatchQueue.main.async {
          self.applyPermission(permission)
          self.callPage("resolvePermission?.(\(requestId), '\(permission.rawValue)')")
        }
      }
    }
  }

  private func showNotification(tag: String, title: String, body: String, isSilent: Bool) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = isSilent ? nil : UNNotificationSound.default

    // The tag is the identifier, so a new notification with the same tag replaces the old one
    let identifier = tag.isEmpty ? UUID().uuidString : tag
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        logger.error("Could not show a notification: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func closeNotification(tag: String) {
    let center = UNUserNotificationCenter.current()
    center.removeDeliveredNotifications(withIdentifiers: [tag])
    center.removePendingNotificationRequests(withIdentifiers: [tag])
  }

  private func setBadge(count: Int) {
    UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { error in
      if let error {
        logger.debug("Could not set the badge: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func logPageMessage(level: String?, message: String) {
    let type: OSLogType
    switch level {
    case "error":
      type = .error
    case "warn", "warning":
      type = .default
    case "debug":
      type = .debug
    default:
      type = .info
    }
    logger.log(level: type, "Page: \(message)")
  }

  /// Calls a method of `window.__liquidgramNative`. Optional chaining makes the call a no-op before `bridge.js`
  /// has run, for example while no page is loaded.
  private func callPage(_ methodCall: String) {
    webView?.evaluateJavaScript("void window.__liquidgramNative?.\(methodCall)") { _, error in
      if let error {
        logger.debug("Could not call the page: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}

extension NativeBridge: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    // Every frame can post to the handler, including bot web apps from other origins, so only the main frame
    // of the app's own origin is heard
    let origin = message.frameInfo.securityOrigin
    guard message.frameInfo.isMainFrame,
          LocalServer.isAppOrigin(scheme: origin.protocol, host: origin.host, port: origin.port),
          let body = message.body as? [String: Any],
          let type = body["type"] as? String else {
      return
    }

    switch type {
    case "requestNotificationPermission":
      if let requestId = body["requestId"] as? Double, requestId.isFinite {
        requestPermission(requestId: requestId)
      }
    case "notify":
      if let tag = body["tag"] as? String {
        showNotification(
          tag: tag,
          title: body["title"] as? String ?? "",
          body: body["body"] as? String ?? "",
          isSilent: body["silent"] as? Bool ?? false
        )
      }
    case "closeNotification":
      if let tag = body["tag"] as? String {
        closeNotification(tag: tag)
      }
    case "badge":
      if let count = body["count"] as? Int {
        setBadge(count: count)
      }
    case "log":
      logPageMessage(level: body["level"] as? String, message: body["message"] as? String ?? "")
    default:
      logger.debug("Unknown message from the page: \(type, privacy: .public)")
    }
  }
}

extension NativeBridge: UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // While the app is active the page shows new messages itself, so a banner would only repeat them
    DispatchQueue.main.async {
      let isActive = UIApplication.shared.applicationState == .active
      completionHandler(isActive ? [] : [.banner, .list, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let tag = response.notification.request.identifier
    let isOpened = response.actionIdentifier == UNNotificationDefaultActionIdentifier
    DispatchQueue.main.async {
      if isOpened {
        self.callPage("notificationClicked?.(\(Self.makeJavaScriptString(tag)))")
      }
      completionHandler()
    }
  }
}

/// Forwards messages to a handler without retaining it
private final class WeakScriptMessageHandler: NSObject {
  private weak var target: WKScriptMessageHandler?

  init(target: WKScriptMessageHandler) {
    self.target = target
    super.init()
  }
}

extension WeakScriptMessageHandler: WKScriptMessageHandler {
  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(userContentController, didReceive: message)
  }
}
