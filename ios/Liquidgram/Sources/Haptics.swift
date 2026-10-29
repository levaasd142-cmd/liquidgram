import UIKit

/// The styles the page asks for through `window.__liquidgramNative.haptic(style)`
enum HapticStyle: String {
  case selection
  case light
  case medium
  case heavy
  case soft
  case rigid
  case success
  case warning
  case error
}

/// Plays haptic feedback for the page. It stays silent while haptics are off in the native settings and plays at
/// most one effect per `minimumInterval`, so a page that fires them in a loop cannot make the phone buzz nonstop.
/// Used on the main queue only.
final class Haptics {
  private static let minimumInterval: TimeInterval = 0.05

  private var lastPlayTime = -TimeInterval.infinity
  private lazy var selectionGenerator = UISelectionFeedbackGenerator()
  private lazy var notificationGenerator = UINotificationFeedbackGenerator()
  private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

  func play(_ style: HapticStyle) {
    guard NativeSettings.isHapticsEnabled else {
      return
    }
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastPlayTime >= Self.minimumInterval else {
      return
    }
    lastPlayTime = now

    switch style {
    case .selection:
      selectionGenerator.selectionChanged()
    case .light:
      playImpact(.light)
    case .medium:
      playImpact(.medium)
    case .heavy:
      playImpact(.heavy)
    case .soft:
      playImpact(.soft)
    case .rigid:
      playImpact(.rigid)
    case .success:
      notificationGenerator.notificationOccurred(.success)
    case .warning:
      notificationGenerator.notificationOccurred(.warning)
    case .error:
      notificationGenerator.notificationOccurred(.error)
    }
  }

  private func playImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    let generator = impactGenerators[style] ?? UIImpactFeedbackGenerator(style: style)
    impactGenerators[style] = generator
    generator.impactOccurred()
  }
}
