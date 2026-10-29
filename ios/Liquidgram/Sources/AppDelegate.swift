import AVFoundation
import os
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "App")

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  private static let sceneConfigurationName = "Default Configuration"

  let bridge = NativeBridge()

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    TestHooks.resetNativeSettingsIfRequested()
    NativeSettings.registerDefaults()
    // Taps on notifications reach the delegate only if it is set before launching finishes
    UNUserNotificationCenter.current().delegate = bridge
    configureAudioSession()
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

  /// `Info.plist` starts the iPhone app in portrait, and its screens stay there, see
  /// `WebViewController.supportedOrientations`. Video that plays full screen in WebKit's own window may turn sideways.
  func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    UIDevice.current.userInterfaceIdiom == .phone ? .allButUpsideDown : .all
  }

  /// Voice messages and videos play even when the Ring/Silent switch is set to silent. With the `audio` background
  /// mode, playback also goes on while the phone is locked or another app is in front, and videos can continue in
  /// Picture in Picture.
  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
    } catch {
      logger.error("Could not set the audio session category: \(error.localizedDescription, privacy: .public)")
    }
  }
}
