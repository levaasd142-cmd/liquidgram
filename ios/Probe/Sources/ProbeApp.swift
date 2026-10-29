import UIKit

@main
final class ProbeAppDelegate: UIResponder, UIApplicationDelegate {
  private static let sceneConfigurationName = "Default Configuration"

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(
      name: Self.sceneConfigurationName,
      sessionRole: connectingSceneSession.role
    )
    configuration.delegateClass = ProbeSceneDelegate.self
    return configuration
  }
}

final class ProbeSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else {
      return
    }
    let window = UIWindow(windowScene: windowScene)
    window.backgroundColor = .white
    window.rootViewController = ProbeViewController()
    window.makeKeyAndVisible()
    self.window = window
  }
}
