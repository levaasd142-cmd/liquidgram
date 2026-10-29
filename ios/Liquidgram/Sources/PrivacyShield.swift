import UIKit

/// Covers the app with a blur and the app logo while it is inactive, so the app switcher and its snapshot show no
/// chats. It is a window of its own above the app's window, so it also covers alerts, share sheets and Safari
/// views that the page presented. Used on the main queue only.
final class PrivacyShield {
  /// Above alerts, below the lock screen
  private static let windowLevel = UIWindow.Level.alert + 1

  private let windowScene: UIWindowScene
  private var window: UIWindow?

  init(windowScene: UIWindowScene) {
    self.windowScene = windowScene
  }

  func show() {
    let window = self.window ?? makeWindow()
    self.window = window
    // Shown without animation, so the first frame after the app resigns already hides the content
    window.isHidden = false
  }

  func hide() {
    window?.isHidden = true
  }

  private func makeWindow() -> UIWindow {
    let window = UIWindow(windowScene: windowScene)
    window.windowLevel = Self.windowLevel
    window.backgroundColor = .clear
    window.rootViewController = PrivacyShieldViewController()
    return window
  }
}

private final class PrivacyShieldViewController: UIViewController {
  /// The shield's window is above the app's window, so it decides the orientation while it is shown
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    WebViewController.supportedOrientations
  }

  override func loadView() {
    let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    blurView.accessibilityIdentifier = "liquidgram.privacyShield"

    let logoView = UIImageView(image: UIImage(named: "LaunchLogo"))
    logoView.translatesAutoresizingMaskIntoConstraints = false
    logoView.isAccessibilityElement = false
    blurView.contentView.addSubview(logoView)
    NSLayoutConstraint.activate([
      logoView.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
      logoView.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor),
    ])
    view = blurView
  }
}
