import AVFoundation
import os
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "App")

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  private static let sceneConfigurationName = "Default Configuration"

  let server = LocalServer()
  let bridge = NativeBridge()

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    TestHooks.resetNativeSettingsIfRequested()
    // Taps on notifications reach the delegate only if it is set before launching finishes
    UNUserNotificationCenter.current().delegate = bridge
    configureAudioSession()
    server.start()
    return true
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
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }

  /// Voice messages and videos play even when the Ring/Silent switch is set to silent
  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
    } catch {
      logger.error("Could not set the audio session category: \(error.localizedDescription, privacy: .public)")
    }
  }
}
