import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var webViewController: WebViewController?

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
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    appDelegate?.server.start()
    // The user may have changed the notification permission in Settings
    appDelegate?.bridge.refreshPermission()
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    // iOS may have reclaimed the listening socket while the app was suspended
    appDelegate?.server.start()
    webViewController?.handleDidBecomeActive()
  }
}
