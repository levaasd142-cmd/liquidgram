import os
import UIKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "AppLock")

private enum Strings {
  static let unlockReason = NSLocalizedString(
    "lock.reason",
    value: "Unlock your chats",
    comment: "Reason in the Touch ID and passcode prompt that unlocks the app"
  )
  static let settingsReason = NSLocalizedString(
    "lock.settingsReason",
    value: "Change the app lock",
    comment: "Reason in the Touch ID and passcode prompt that confirms turning the app lock on or off"
  )
}

/// Locks the app behind Face ID, Touch ID, Optic ID or the device passcode and hides the chats in the app switcher.
///
/// With the lock on, the app starts locked and locks again after it was in the background for `appLockDelay`
/// seconds or more. The lock screen is a window above everything else, including alerts, share sheets and Safari
/// views, and asks for authentication when the scene becomes active. While the lock or the privacy shield is on,
/// a blur covers the app whenever it is inactive. The scene delegate forwards its lifecycle here; everything runs
/// on the main queue.
final class AppLock {
  /// Above the privacy shield and every alert
  private static let lockWindowLevel = UIWindow.Level.alert + 2
  private static let unlockAnimationDuration: TimeInterval = 0.25

  /// Called after the app unlocks, so that actions held back while it was locked reach the page
  var didUnlock: (() -> Void)?
  private(set) var isLocked = false

  private let windowScene: UIWindowScene
  private weak var mainWindow: UIWindow?
  private let privacyShield: PrivacyShield
  private var lockWindow: UIWindow?
  private var isAuthenticating = false
  private var isConfirmingSettingsChange = false
  private var shouldAuthenticateOnActivation = false
  /// The continuous clock keeps counting while the device sleeps and ignores changes to the device clock
  private var backgroundEntryTime: ContinuousClock.Instant?

  init(windowScene: UIWindowScene, mainWindow: UIWindow) {
    self.windowScene = windowScene
    self.mainWindow = mainWindow
    privacyShield = PrivacyShield(windowScene: windowScene)
  }

  /// The privacy shield setting, or the lock, which needs the shield to keep its content private
  private var isShieldEnabled: Bool {
    NativeSettings.isPrivacyShieldEnabled || NativeSettings.isAppLockEnabled
  }

  /// Shows the lock before the first frame of a cold launch
  func lockAtLaunchIfNeeded() {
    guard NativeSettings.isAppLockEnabled else {
      return
    }
    lock(shouldAuthenticateOnActivation: true)
  }

  /// Locks the app at the page's request. The prompt waits for the unlock button, since the user just chose to lock.
  func lockNow() {
    guard NativeSettings.isAppLockEnabled else {
      logger.info("Ignored a request to lock while the app lock is off")
      return
    }
    lock(shouldAuthenticateOnActivation: false)
  }

  func sceneWillResignActive() {
    // A prompt that confirms a settings change makes the app inactive while the user is looking at it
    guard isShieldEnabled, !isConfirmingSettingsChange else {
      return
    }
    privacyShield.show()
  }

  func sceneDidEnterBackground() {
    backgroundEntryTime = .now
    // The app switcher takes its snapshot now, also when a prompt kept the shield down on resigning
    if isShieldEnabled {
      privacyShield.show()
    }
    // iOS cancels a prompt in progress when the app leaves; a new one starts when the user returns
    if isLocked {
      shouldAuthenticateOnActivation = true
    }
  }

  func sceneWillEnterForeground() {
    guard let backgroundEntryTime else {
      return
    }
    self.backgroundEntryTime = nil
    guard NativeSettings.isAppLockEnabled, !isLocked else {
      return
    }
    if backgroundEntryTime.duration(to: .now) >= .seconds(NativeSettings.appLockDelay) {
      lock(shouldAuthenticateOnActivation: true)
    }
  }

  func sceneDidBecomeActive() {
    guard isLocked else {
      privacyShield.hide()
      return
    }
    if shouldAuthenticateOnActivation {
      authenticate()
    }
  }

  /// Asks the owner to authenticate before the page turns the lock on or off. While the app is locked, or the lock
  /// screen is already asking, the request is cancelled.
  func confirmSettingsChange(completion: @escaping (AuthenticationResult) -> Void) {
    guard !isLocked, !isAuthenticating else {
      completion(.cancelled)
      return
    }
    isAuthenticating = true
    isConfirmingSettingsChange = true
    DeviceAuthentication.authenticate(reason: Strings.settingsReason) { [weak self] result in
      self?.isAuthenticating = false
      self?.isConfirmingSettingsChange = false
      completion(result)
    }
  }

  private func lock(shouldAuthenticateOnActivation: Bool) {
    guard !isLocked else {
      return
    }
    isLocked = true
    self.shouldAuthenticateOnActivation = shouldAuthenticateOnActivation
    // The keyboard would stay above the lock screen, so the page's field gives up the focus
    mainWindow?.endEditing(true)

    let controller = LockViewController(biometryType: DeviceAuthentication.currentBiometryType()) { [weak self] in
      self?.authenticate()
    }
    let window = UIWindow(windowScene: windowScene)
    window.windowLevel = Self.lockWindowLevel
    window.rootViewController = controller
    window.makeKeyAndVisible()
    lockWindow = window
    logger.info("Locked the app")
  }

  private func authenticate() {
    guard isLocked, !isAuthenticating else {
      return
    }
    shouldAuthenticateOnActivation = false
    isAuthenticating = true
    DeviceAuthentication.authenticate(reason: Strings.unlockReason) { [weak self] result in
      guard let self else {
        return
      }
      self.isAuthenticating = false
      switch result {
      case .success:
        self.unlock()
      case .passcodeNotSet:
        // Without a passcode the device cannot verify its owner, so the lock turns itself off instead of
        // locking the user out
        logger.notice("The device has no passcode; turning the app lock off")
        NativeSettings.isAppLockEnabled = false
        self.unlock()
      case .failed, .cancelled:
        // The unlock button starts another attempt
        break
      }
    }
  }

  private func unlock() {
    guard isLocked else {
      return
    }
    isLocked = false
    privacyShield.hide()
    mainWindow?.makeKey()

    let window = lockWindow
    lockWindow = nil
    UIView.animate(
      withDuration: Self.unlockAnimationDuration,
      animations: {
        window?.alpha = 0
      },
      completion: { _ in
        window?.isHidden = true
        // VoiceOver moves from the lock screen to the app
        UIAccessibility.post(notification: .screenChanged, argument: nil)
      }
    )
    logger.info("Unlocked the app")
    didUnlock?()
  }
}
