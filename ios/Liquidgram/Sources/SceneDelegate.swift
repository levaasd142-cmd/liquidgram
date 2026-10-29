import os
import UIKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "Scene")

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var webViewController: WebViewController?
  private var appLock: AppLock?

  private var appDelegate: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene, let appDelegate else {
      return
    }
    let controller = WebViewController(server: appDelegate.server, bridge: appDelegate.bridge)
    let window = UIWindow(windowScene: windowScene)
    window.backgroundColor = WebViewController.backgroundColor
    window.rootViewController = controller
    window.makeKeyAndVisible()
    self.window = window
    webViewController = controller

    let appLock = AppLock(windowScene: windowScene, mainWindow: window)
    appLock.didUnlock = { [weak bridge = appDelegate.bridge] in
      bridge?.deliverPendingActions()
    }
    appDelegate.bridge.appLock = appLock
    self.appLock = appLock
    // The lock window appears in the same frame as the app's window, so no content shows before it
    appLock.lockAtLaunchIfNeeded()

    // A quick action or a link that launched the app waits in the bridge until the page is ready
    if let shortcutItem = connectionOptions.shortcutItem {
      performQuickAction(shortcutItem)
    }
    openLinks(connectionOptions.urlContexts)
  }

  func sceneWillResignActive(_ scene: UIScene) {
    appLock?.sceneWillResignActive()
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    appLock?.sceneDidEnterBackground()
    appDelegate?.server.suspend()
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    appLock?.sceneWillEnterForeground()
    // iOS may have reclaimed the listening socket while the app was suspended, and another app may hold the port
    appDelegate?.server.resume()
    // The user may have changed the notification permission in Settings
    appDelegate?.bridge.refreshPermission()
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    appDelegate?.server.start()
    appLock?.sceneDidBecomeActive()
    webViewController?.handleDidBecomeActive()
  }

  func windowScene(
    _ windowScene: UIWindowScene,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    completionHandler(performQuickAction(shortcutItem))
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    openLinks(URLContexts)
  }

  @discardableResult
  private func performQuickAction(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
    guard let action = NativeAction(shortcutItemType: shortcutItem.type) else {
      logger.error("Unknown quick action \(shortcutItem.type, privacy: .public)")
      return false
    }
    appDelegate?.bridge.perform(action)
    return true
  }

  /// `liquidgram:` and `tg:` links open in the web app
  private func openLinks(_ urlContexts: Set<UIOpenURLContext>) {
    for context in urlContexts {
      guard let action = NativeAction(url: context.url) else {
        logger.info("Ignored a link that is not a Telegram link")
        continue
      }
      appDelegate?.bridge.perform(action)
    }
  }
}
