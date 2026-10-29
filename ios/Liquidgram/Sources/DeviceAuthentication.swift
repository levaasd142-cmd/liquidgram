import Foundation
import LocalAuthentication
import os

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "Authentication")

/// How the device verifies its owner, as the page's settings snapshot and the lock screen name it
enum BiometryType: String {
  case faceID
  case touchID
  case opticID
  /// No biometry is enrolled or allowed for the app, but the device has a passcode
  case passcode
  /// The device has no passcode, so it cannot verify its owner at all
  case none
}

enum AuthenticationResult {
  case success
  case failed
  case cancelled
  /// The device has no passcode any more
  case passcodeNotSet
}

/// Face ID, Touch ID or Optic ID with the device passcode as the fallback (`LAPolicy.deviceOwnerAuthentication`).
/// While a UI test passes `-LiquidgramFakeAuthentication`, the outcome comes from the test instead.
enum DeviceAuthentication {
  /// Launch argument `-LiquidgramFakeAuthenticationDelay <seconds>`: a faked authentication that takes longer
  /// than the launch of the app, so a UI test sees the lock screen before it opens
  private static let fakeOutcomeDelayArgument = "LiquidgramFakeAuthenticationDelay"
  private static let defaultFakeOutcomeDelay: TimeInterval = 0.3
  private static let fakeSuccessOutcome = "success"
  private static let fakeCancelOutcome = "cancel"

  /// Read only while `TestHooks.fakeAuthenticationOutcome` is set, which only test builds allow
  private static var fakeOutcomeDelay: TimeInterval {
    let delay = UserDefaults.standard.double(forKey: fakeOutcomeDelayArgument)
    return delay > 0 ? delay : defaultFakeOutcomeDelay
  }

  static func currentBiometryType() -> BiometryType {
    if TestHooks.fakeAuthenticationOutcome != nil {
      return .faceID
    }

    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      return .none
    }
    // `biometryType` is set once a biometric policy was checked. Biometry cannot be used while nothing is enrolled,
    // Face ID is not allowed for the app or biometry is locked out; the passcode still works then.
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      return .passcode
    }
    switch context.biometryType {
    case .faceID:
      return .faceID
    case .touchID:
      return .touchID
    default:
      if #available(iOS 17.0, *), context.biometryType == .opticID {
        return .opticID
      }
      return .passcode
    }
  }

  /// Asks the owner to authenticate and calls `completion` once on the main queue
  static func authenticate(reason: String, completion: @escaping (AuthenticationResult) -> Void) {
    if let outcome = TestHooks.fakeAuthenticationOutcome {
      let result = makeFakeResult(outcome)
      DispatchQueue.main.asyncAfter(deadline: .now() + fakeOutcomeDelay) {
        completion(result)
      }
      return
    }

    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      let result = makeResult(error)
      DispatchQueue.main.async {
        completion(result)
      }
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { isSuccess, error in
      // LocalAuthentication cancels the evaluation when its context is released, so the reply keeps it
      withExtendedLifetime(context) {}
      let result = isSuccess ? AuthenticationResult.success : makeResult(error)
      DispatchQueue.main.async {
        completion(result)
      }
    }
  }

  private static func makeResult(_ error: Error?) -> AuthenticationResult {
    guard let error = error as? LAError else {
      return .failed
    }
    switch error.code {
    case .userCancel, .systemCancel, .appCancel, .userFallback, .notInteractive:
      return .cancelled
    case .passcodeNotSet:
      return .passcodeNotSet
    default:
      logger.info("Authentication failed with code \(error.code.rawValue, privacy: .public)")
      return .failed
    }
  }

  private static func makeFakeResult(_ outcome: String) -> AuthenticationResult {
    switch outcome {
    case fakeSuccessOutcome:
      return .success
    case fakeCancelOutcome:
      return .cancelled
    default:
      return .failed
    }
  }
}
