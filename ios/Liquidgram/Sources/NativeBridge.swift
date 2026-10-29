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

/// The messages that `bridge.js` posts to the `liquidgram` handler
private enum MessageType: String {
  case requestNotificationPermission
  case notify
  case closeNotification
  case badge
  case log
  case haptic
  case appReady
  case lockNow
  case openSystemSettings
  case getNativeSettings
  case setNativeSetting
  case setAppIcon
  case recordRoundVideo
  case releaseMedia
}

/// Native side of the contract with `Resources/bridge.js`. Two user scripts run at document start in the main
/// frame: one sets `window.__liquidgramNative` and the other is `bridge.js`, which adds the page's API to it.
/// The page posts messages to the `liquidgram` handler, and the bridge answers through `resolvePermission`,
/// `setPermission`, `notificationClicked`, `resolveRequest`, `resolveRoundVideo` and `dispatchAction` of
/// `window.__liquidgramNative`.
/// Native actions wait until the current page reports `appReady` and the app is unlocked.
/// The app delegate creates the bridge at launch, so it can receive taps on notifications from the start.
/// All state is used on the main queue.
final class NativeBridge: NSObject {
  static let messageHandlerName = "liquidgram"

  private static let bridgeScriptName = "bridge"
  private static let bridgeScriptExtension = "js"
  private static let notificationOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
  private static let maxTagLength = 256
  private static let maxTitleLength = 1024
  private static let maxBodyLength = 4096
  private static let maxLogMessageLength = 8192
  private static let maxBadgeCount = 99_999
  private static let maxPendingActions = 8
  /// Actions that waited longer, for example while the user signed in, are dropped
  private static let pendingActionLifetime: Duration = .seconds(120)

  weak var webView: WKWebView?
  /// Actions wait while the lock is up, and the lock confirms changes of its own setting
  weak var appLock: AppLock? {
    didSet {
      requestHandler.appLock = appLock
    }
  }

  private weak var userContentController: WKUserContentController?
  private let requestHandler = NativeRequestHandler()
  private let roundVideoRecorder = RoundVideoRecorder()
  private let haptics = Haptics()
  private let appVersion: String
  private let bridgeScript: String?
  private var permission = NotificationPermission.notDetermined
  /// Counts the documents the web view committed, so a response never reaches a page that did not ask for it
  private var pageGeneration = 0
  private var isPageReady = false
  private var pendingActions: [(action: NativeAction, time: ContinuousClock.Instant)] = []
  private var hasPerformedTestAction = false

  override init() {
    appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    bridgeScript = Self.loadBridgeScript()
    super.init()
    // No page knows the paths of recordings from an earlier launch
    MediaStore.shared.removeAllFiles()
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

  /// A new document committed in the web view's main frame. It has no action handler yet, and responses to the
  /// previous document's requests must not reach it.
  func pageDidCommit() {
    pageGeneration += 1
    isPageReady = false
    // The recorder and the recordings belong to the page that is gone
    roundVideoRecorder.cancel()
    MediaStore.shared.releaseAll()
  }

  /// Sends an action to the page once the page is ready and the app is unlocked. A transient action, such as a
  /// status bar tap, is dropped instead when it cannot be delivered right away.
  func perform(_ action: NativeAction) {
    if action.isTransient {
      if canDeliverActions {
        dispatch(action)
      }
      return
    }
    pendingActions.append((action: action, time: .now))
    if pendingActions.count > Self.maxPendingActions {
      pendingActions.removeFirst(pendingActions.count - Self.maxPendingActions)
    }
    deliverPendingActions()
  }

  /// Sends the actions that waited for the page or for the unlock
  func deliverPendingActions() {
    guard canDeliverActions else {
      return
    }
    let now = ContinuousClock.Instant.now
    let actions = pendingActions.filter { $0.time.duration(to: now) <= Self.pendingActionLifetime }
    pendingActions.removeAll()
    for pending in actions {
      dispatch(pending.action)
    }
  }

  private var canDeliverActions: Bool {
    isPageReady && webView != nil && appLock?.isLocked != true
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

  /// Encodes an object as JSON, which is also a JavaScript expression
  private static func makeJSON(_ object: [String: Any]) -> String? {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object),
          let json = String(data: data, encoding: .utf8) else {
      logger.error("Could not encode a message for the page")
      return nil
    }
    return json
  }

  /// The injected state is fixed when a page starts, so the scripts are rebuilt whenever the permission
  /// changes and every later load, such as a reload after the web process ends, gets the current value
  private func installUserScripts() {
    guard let userContentController else {
      return
    }
    userContentController.removeAllUserScripts()
    for script in TestHooks.makeUserScripts() {
      userContentController.addUserScript(script)
    }

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

  private func handle(_ type: MessageType, body: [String: Any]) {
    switch type {
    case .requestNotificationPermission:
      if let requestId = NativeRequestHandler.readInteger(body["requestId"]) {
        requestPermission(requestId: requestId)
      }
    case .notify:
      guard let tag = body["tag"] as? String, tag.count <= Self.maxTagLength else {
        return
      }
      showNotification(
        tag: tag,
        title: String((body["title"] as? String ?? "").prefix(Self.maxTitleLength)),
        body: String((body["body"] as? String ?? "").prefix(Self.maxBodyLength)),
        isSilent: NativeRequestHandler.readBool(body["silent"]) ?? false
      )
    case .closeNotification:
      if let tag = body["tag"] as? String, tag.count <= Self.maxTagLength {
        closeNotification(tag: tag)
      }
    case .badge:
      if let count = NativeRequestHandler.readInteger(body["count"]) {
        setBadge(count: min(max(0, count), Self.maxBadgeCount))
      }
    case .log:
      let message = String((body["message"] as? String ?? "").prefix(Self.maxLogMessageLength))
      logPageMessage(level: body["level"] as? String, message: message)
    case .haptic:
      if let style = (body["style"] as? String).flatMap(HapticStyle.init(rawValue:)) {
        haptics.play(style)
      }
    case .appReady:
      handleAppReady()
    case .lockNow:
      appLock?.lockNow()
    case .openSystemSettings:
      openSystemSettings()
    case .getNativeSettings:
      handleRequest(.getNativeSettings, body: body)
    case .setNativeSetting:
      handleRequest(.setNativeSetting, body: body)
    case .setAppIcon:
      handleRequest(.setAppIcon, body: body)
    case .recordRoundVideo:
      if let requestId = NativeRequestHandler.readInteger(body["requestId"]) {
        recordRoundVideo(
          requestId: requestId,
          canSendOneTimeMedia: NativeRequestHandler.readBool(body["canSendOneTimeMedia"]) ?? false
        )
      }
    case .releaseMedia:
      if let path = body["url"] as? String {
        roundVideoRecorder.releaseMedia(path: path, in: webView?.window)
      }
    }
  }

  /// The web app mounted its signed-in interface and registered its action handler. A remount announces it again.
  private func handleAppReady() {
    isPageReady = true
    if let webView {
      TestHooks.pageDidBecomeReady(in: webView)
    }
    if !hasPerformedTestAction, let type = TestHooks.testAction {
      hasPerformedTestAction = true
      if let action = NativeAction(type: type) {
        perform(action)
      } else {
        logger.error("Unknown test action \(type, privacy: .public)")
      }
    }
    deliverPendingActions()
  }

  private func handleRequest(_ type: NativeRequestHandler.RequestType, body: [String: Any]) {
    guard let requestId = NativeRequestHandler.readInteger(body["requestId"]) else {
      return
    }
    let generation = pageGeneration
    requestHandler.handle(type, body: body) { [weak self] response in
      self?.resolveRequest(requestId, response: response, generation: generation)
    }
  }

  /// Opens the round video recorder; the page gets the recording's path and details, or `null` for nothing to send
  private func recordRoundVideo(requestId: Int, canSendOneTimeMedia: Bool) {
    let generation = pageGeneration
    roundVideoRecorder.record(canSendOneTimeMedia: canSendOneTimeMedia, from: webView) { [weak self] result in
      guard let self, generation == self.pageGeneration else {
        // No other page knows the path
        if let path = result?["url"] as? String {
          MediaStore.shared.release(path: path)
        }
        return
      }
      let json = result.flatMap(Self.makeJSON) ?? "null"
      self.callPage("resolveRoundVideo?.(\(requestId), \(json))")
    }
  }

  private func resolveRequest(_ requestId: Int, response: [String: Any], generation: Int) {
    // A newer page may use the same request id for another request
    guard generation == pageGeneration else {
      logger.debug("Dropped the response to a request of a page that is gone")
      return
    }
    guard let json = Self.makeJSON(response) else {
      return
    }
    callPage("resolveRequest?.(\(requestId), \(json))")
  }

  private func dispatch(_ action: NativeAction) {
    guard let json = Self.makeJSON(action.message) else {
      return
    }
    callPage("dispatchAction?.(\(json))")
  }

  private func openSystemSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      return
    }
    UIApplication.shared.open(url)
  }

  private func applyPermission(_ newPermission: NotificationPermission) {
    if newPermission != permission {
      permission = newPermission
      installUserScripts()
    }
    callPage("setPermission?.('\(permission.rawValue)')")
  }

  private func requestPermission(requestId: Int) {
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
    UNUserNotificationCenter.current().setBadgeCount(count) { error in
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
          let typeName = body["type"] as? String else {
      return
    }
    guard let type = MessageType(rawValue: typeName) else {
      // A request of an unknown type still gets its one answer, so the page does not wait for the timeout
      if let requestId = NativeRequestHandler.readInteger(body["requestId"]) {
        resolveRequest(requestId, response: NativeRequestHandler.makeFailure(.invalid), generation: pageGeneration)
      }
      logger.debug("Unknown message from the page: \(typeName, privacy: .public)")
      return
    }
    handle(type, body: body)
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
