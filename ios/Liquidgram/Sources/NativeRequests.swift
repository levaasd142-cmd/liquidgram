import Foundation
import os
import UIKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "NativeRequests")

/// Answers the page's `window.__liquidgramNative.request(type, payload)` calls about the native settings. Every
/// request gets exactly one response, `{ ok, error?, settings }`, and `settings` is always the current snapshot.
/// Turning the app lock on or off needs the owner's authentication. Used on the main queue only.
final class NativeRequestHandler {
  typealias Responder = ([String: Any]) -> Void

  enum RequestType: String {
    case getNativeSettings
    case setNativeSetting
    case setAppIcon
  }

  enum Failure: String {
    case authFailed
    case cancelled
    case notAvailable
    case invalid
  }

  /// The largest integer a JavaScript number holds exactly
  private static let maxSafeInteger: Double = 9_007_199_254_740_991

  weak var appLock: AppLock?

  /// The response to a request the app cannot handle, such as one of an unknown type
  static func makeFailure(_ failure: Failure) -> [String: Any] {
    ["ok": false, "error": failure.rawValue, "settings": NativeSettings.makeSnapshot()]
  }

  /// A JavaScript boolean. WebKit passes it as a `CFBoolean`, so numbers do not count.
  static func readBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
      return nil
    }
    return number.boolValue
  }

  /// A JavaScript number that is a safe integer
  static func readInteger(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
      return nil
    }
    let double = number.doubleValue
    guard double.isFinite, double == double.rounded(), abs(double) <= maxSafeInteger else {
      return nil
    }
    return Int(double)
  }

  private static func makeSuccess() -> [String: Any] {
    ["ok": true, "settings": NativeSettings.makeSnapshot()]
  }

  func handle(_ type: RequestType, body: [String: Any], respond: @escaping Responder) {
    switch type {
    case .getNativeSettings:
      respond(Self.makeSuccess())
    case .setNativeSetting:
      setSetting(key: body["key"], value: body["value"], respond: respond)
    case .setAppIcon:
      setAppIcon(body, respond: respond)
    }
  }

  private func setSetting(key keyValue: Any?, value: Any?, respond: @escaping Responder) {
    guard let keyName = keyValue as? String, let key = NativeSettings.Key(rawValue: keyName) else {
      respond(Self.makeFailure(.invalid))
      return
    }

    switch key {
    case .appLockEnabled:
      guard let isEnabled = Self.readBool(value) else {
        respond(Self.makeFailure(.invalid))
        return
      }
      setAppLockEnabled(isEnabled, respond: respond)
    case .appLockDelay:
      guard let delay = Self.readInteger(value), NativeSettings.appLockDelays.contains(delay) else {
        respond(Self.makeFailure(.invalid))
        return
      }
      NativeSettings.appLockDelay = delay
      respond(Self.makeSuccess())
    case .privacyShieldEnabled, .hapticsEnabled, .inAppBrowserEnabled:
      guard let isEnabled = Self.readBool(value) else {
        respond(Self.makeFailure(.invalid))
        return
      }
      setFlag(key, isEnabled: isEnabled)
      respond(Self.makeSuccess())
    }
  }

  private func setFlag(_ key: NativeSettings.Key, isEnabled: Bool) {
    switch key {
    case .privacyShieldEnabled:
      NativeSettings.isPrivacyShieldEnabled = isEnabled
    case .hapticsEnabled:
      NativeSettings.isHapticsEnabled = isEnabled
    case .inAppBrowserEnabled:
      NativeSettings.isInAppBrowserEnabled = isEnabled
    case .appLockEnabled, .appLockDelay:
      break
    }
  }

  /// The page can never change the lock without the owner: the change waits for a successful authentication
  private func setAppLockEnabled(_ isEnabled: Bool, respond: @escaping Responder) {
    guard isEnabled != NativeSettings.isAppLockEnabled else {
      respond(Self.makeSuccess())
      return
    }
    guard let appLock else {
      respond(Self.makeFailure(.notAvailable))
      return
    }

    appLock.confirmSettingsChange { result in
      switch result {
      case .success:
        NativeSettings.isAppLockEnabled = isEnabled
        respond(Self.makeSuccess())
      case .passcodeNotSet:
        // Without a device passcode the lock cannot work: it can be turned off, as the lock screen does itself,
        // but not on
        if isEnabled {
          respond(Self.makeFailure(.notAvailable))
        } else {
          NativeSettings.isAppLockEnabled = false
          respond(Self.makeSuccess())
        }
      case .cancelled:
        respond(Self.makeFailure(.cancelled))
      case .failed:
        respond(Self.makeFailure(.authFailed))
      }
    }
  }

  private func setAppIcon(_ body: [String: Any], respond: @escaping Responder) {
    let name: String?
    switch body["name"] {
    case is NSNull:
      name = nil
    case let iconName as String where NativeSettings.availableAlternateIconNames.contains(iconName):
      name = iconName
    default:
      respond(Self.makeFailure(.invalid))
      return
    }

    let application = UIApplication.shared
    guard application.supportsAlternateIcons else {
      respond(Self.makeFailure(.notAvailable))
      return
    }
    // iOS confirms every change with an alert, so an unchanged icon is not set again
    guard application.alternateIconName != name else {
      respond(Self.makeSuccess())
      return
    }
    application.setAlternateIconName(name) { error in
      // The completion runs on a background queue
      DispatchQueue.main.async {
        if let error {
          logger.error("Could not change the app icon: \(error.localizedDescription, privacy: .public)")
          respond(Self.makeFailure(.notAvailable))
        } else {
          respond(Self.makeSuccess())
        }
      }
    }
  }
}
