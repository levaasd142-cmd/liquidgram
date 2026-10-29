import Foundation
import UIKit

/// Settings of the native app that the web app shows under Settings → Liquidgram → iPhone. They live in
/// `UserDefaults.standard` and are read from it every time, so launch arguments such as `-appLockEnabled YES`
/// override them in UI tests.
enum NativeSettings {
  /// The keys in `UserDefaults` and in the page's `setNativeSetting` requests
  enum Key: String {
    case appLockEnabled
    case appLockDelay
    case privacyShieldEnabled
    case hapticsEnabled
    case inAppBrowserEnabled
  }

  /// Seconds in the background after which the app locks again; 0 locks it every time
  static let appLockDelays = [0, 60, 300, 900, 3600]
  /// The alternate app icons in the order the web app's picker shows them
  static let alternateIconNames = ["AppIconMidnight", "AppIconAurora", "AppIconGlass", "AppIconClassic"]

  private static let defaultAppLockDelay = 60
  private static let iconsInfoKey = "CFBundleIcons"
  private static let alternateIconsInfoKey = "CFBundleAlternateIcons"

  private static var defaults: UserDefaults {
    .standard
  }

  static var isAppLockEnabled: Bool {
    get { defaults.bool(forKey: Key.appLockEnabled.rawValue) }
    set { defaults.set(newValue, forKey: Key.appLockEnabled.rawValue) }
  }

  static var appLockDelay: Int {
    get {
      let delay = defaults.integer(forKey: Key.appLockDelay.rawValue)
      return appLockDelays.contains(delay) ? delay : defaultAppLockDelay
    }
    set { defaults.set(newValue, forKey: Key.appLockDelay.rawValue) }
  }

  static var isPrivacyShieldEnabled: Bool {
    get { defaults.bool(forKey: Key.privacyShieldEnabled.rawValue) }
    set { defaults.set(newValue, forKey: Key.privacyShieldEnabled.rawValue) }
  }

  static var isHapticsEnabled: Bool {
    get { defaults.bool(forKey: Key.hapticsEnabled.rawValue) }
    set { defaults.set(newValue, forKey: Key.hapticsEnabled.rawValue) }
  }

  static var isInAppBrowserEnabled: Bool {
    get { defaults.bool(forKey: Key.inAppBrowserEnabled.rawValue) }
    set { defaults.set(newValue, forKey: Key.inAppBrowserEnabled.rawValue) }
  }

  /// The alternate icons that the app bundle declares, in display order. The asset catalog compiler lists them in
  /// `CFBundleIcons`, so an icon set missing from the build is never offered.
  static var availableAlternateIconNames: [String] {
    let icons = Bundle.main.object(forInfoDictionaryKey: iconsInfoKey) as? [String: Any]
    let alternateIcons = icons?[alternateIconsInfoKey] as? [String: Any] ?? [:]
    return alternateIconNames.filter { alternateIcons[$0] != nil }
  }

  /// Registers the values that apply until the user changes a setting. Registered defaults are not stored, so
  /// they never mask a launch argument or a value the user chose.
  static func registerDefaults() {
    defaults.register(defaults: [
      Key.appLockEnabled.rawValue: false,
      Key.appLockDelay.rawValue: defaultAppLockDelay,
      Key.privacyShieldEnabled.rawValue: true,
      Key.hapticsEnabled.rawValue: true,
      Key.inAppBrowserEnabled.rawValue: true,
    ])
  }

  /// The settings as the page receives them in every response to its requests
  static func makeSnapshot() -> [String: Any] {
    let application = UIApplication.shared
    let appIcon: Any = application.alternateIconName ?? NSNull()
    return [
      Key.appLockEnabled.rawValue: isAppLockEnabled,
      Key.appLockDelay.rawValue: appLockDelay,
      "biometryType": DeviceAuthentication.currentBiometryType().rawValue,
      Key.privacyShieldEnabled.rawValue: isPrivacyShieldEnabled,
      Key.hapticsEnabled.rawValue: isHapticsEnabled,
      Key.inAppBrowserEnabled.rawValue: isInAppBrowserEnabled,
      "appIcon": appIcon,
      "appIcons": availableAlternateIconNames,
      "supportsAlternateIcons": application.supportsAlternateIcons,
    ]
  }
}
