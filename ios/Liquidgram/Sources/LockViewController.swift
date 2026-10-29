import UIKit

private enum Strings {
  static let title = NSLocalizedString(
    "lock.title",
    value: "Liquidgram is locked",
    comment: "Title of the screen that covers the app until the user authenticates"
  )
  static let unlockWithFaceID = NSLocalizedString(
    "lock.unlock.faceID",
    value: "Unlock with Face ID",
    comment: "Button of the lock screen on devices with Face ID"
  )
  static let unlockWithTouchID = NSLocalizedString(
    "lock.unlock.touchID",
    value: "Unlock with Touch ID",
    comment: "Button of the lock screen on devices with Touch ID"
  )
  static let unlockWithOpticID = NSLocalizedString(
    "lock.unlock.opticID",
    value: "Unlock with Optic ID",
    comment: "Button of the lock screen on devices with Optic ID"
  )
  static let unlock = NSLocalizedString(
    "lock.unlock.passcode",
    value: "Unlock",
    comment: "Button of the lock screen when the device passcode is the only way to authenticate"
  )
}

/// The lock screen: the app logo where the launch screen shows it, a title and a button that starts the
/// authentication again after a failed or cancelled attempt. The colors come from the launch screen and follow
/// light and dark mode.
final class LockViewController: UIViewController {
  /// The web app's accent color
  private static let accentColor = UIColor(red: 0x33 / 255, green: 0x90 / 255, blue: 0xEC / 255, alpha: 1)
  private static let titleFontSize: CGFloat = 22
  private static let spacing: CGFloat = 24
  private static let minimumTopSpacing: CGFloat = 16
  private static let buttonImagePadding: CGFloat = 8

  private let biometryType: BiometryType
  private let unlockAction: () -> Void
  private let titleLabel = UILabel()

  init(biometryType: BiometryType, unlockAction: @escaping () -> Void) {
    self.biometryType = biometryType
    self.unlockAction = unlockAction
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func loadView() {
    let containerView = UIView()
    containerView.backgroundColor = WebViewController.backgroundColor
    containerView.accessibilityIdentifier = "liquidgram.lock"
    // VoiceOver stays on the lock screen instead of reaching the chats behind it
    containerView.accessibilityViewIsModal = true

    let logoView = UIImageView(image: UIImage(named: "LaunchLogo"))
    logoView.translatesAutoresizingMaskIntoConstraints = false
    logoView.isAccessibilityElement = false

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = Strings.title
    titleLabel.textColor = .label
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 0
    titleLabel.font = UIFontMetrics(forTextStyle: .title2)
      .scaledFont(for: .systemFont(ofSize: Self.titleFontSize, weight: .bold))
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.accessibilityTraits = .header

    let unlockButton = UIButton(
      configuration: makeButtonConfiguration(),
      primaryAction: UIAction { [weak self] _ in
        self?.unlockAction()
      }
    )
    unlockButton.translatesAutoresizingMaskIntoConstraints = false
    unlockButton.tintColor = Self.accentColor
    unlockButton.accessibilityIdentifier = "liquidgram.lock.unlock"

    containerView.addSubview(logoView)
    containerView.addSubview(titleLabel)
    containerView.addSubview(unlockButton)

    let safeArea = containerView.safeAreaLayoutGuide
    let margins = containerView.layoutMarginsGuide
    // The logo stays where the launch screen shows it and only moves up when large text needs the room
    let logoCenter = logoView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
    logoCenter.priority = .defaultHigh
    let logoTop = logoView.topAnchor.constraint(
      greaterThanOrEqualTo: safeArea.topAnchor,
      constant: Self.minimumTopSpacing
    )
    logoTop.priority = .required - 1
    NSLayoutConstraint.activate([
      logoView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      logoCenter,
      logoTop,
      titleLabel.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: Self.spacing),
      titleLabel.leadingAnchor.constraint(equalTo: margins.leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: margins.trailingAnchor),
      unlockButton.topAnchor.constraint(greaterThanOrEqualTo: titleLabel.bottomAnchor, constant: Self.spacing),
      unlockButton.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
      unlockButton.leadingAnchor.constraint(greaterThanOrEqualTo: margins.leadingAnchor),
      unlockButton.trailingAnchor.constraint(lessThanOrEqualTo: margins.trailingAnchor),
      unlockButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -Self.spacing),
    ])
    view = containerView
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
  }

  private func makeButtonConfiguration() -> UIButton.Configuration {
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *) {
      configuration = .prominentGlass()
    } else {
      configuration = .filled()
      configuration.cornerStyle = .capsule
    }
    configuration.buttonSize = .large
    configuration.imagePadding = Self.buttonImagePadding

    switch biometryType {
    case .faceID:
      configuration.title = Strings.unlockWithFaceID
      configuration.image = UIImage(systemName: "faceid")
    case .touchID:
      configuration.title = Strings.unlockWithTouchID
      configuration.image = UIImage(systemName: "touchid")
    case .opticID:
      configuration.title = Strings.unlockWithOpticID
      configuration.image = UIImage(systemName: "opticid")
    case .passcode, .none:
      configuration.title = Strings.unlock
      configuration.image = UIImage(systemName: "lock.open.fill")
    }
    return configuration
  }
}
