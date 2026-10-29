import AVFoundation
import os
import UIKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "RoundVideoTest")

extension TestHooks {
  /// Launch argument `-LiquidgramFakeRoundVideo YES`: the round video recorder records generated frames and silence
  /// instead of the camera and the microphone, which the simulator lacks, and reports what it did as the
  /// accessibility value of `roundVideoReportIdentifier`
  static let fakeRoundVideoArgument = "LiquidgramFakeRoundVideo"
  static let roundVideoReportIdentifier = "liquidgram.roundVideo.testReport"

  static var isFakeRoundVideoEnabled: Bool {
    isEnabled && UserDefaults.standard.bool(forKey: fakeRoundVideoArgument)
  }
}

/// What the round video recorder did, for the UI tests: the events in order and, for a sent recording, what the file
/// holds as read from its boxes and whether its first frame decodes. Active only while
/// `TestHooks.isFakeRoundVideoEnabled`. Used on the main queue.
enum RoundVideoTestReport {
  private static let labelAlpha: CGFloat = 0.02
  /// The decoded frame comes from half a second in, after the first key frame
  private static let decodeTime = CMTime(value: 1, timescale: 2)

  private static var events: [String] = []
  private static var details: [String: Any] = [:]
  private static weak var label: UILabel?

  static func record(_ event: String, in window: UIWindow?) {
    guard TestHooks.isFakeRoundVideoEnabled else {
      return
    }
    events.append(event)
    details["storedFiles"] = MediaStore.shared.count
    show(in: window)
  }

  /// Describes a recording that is about to reach the page, then calls `completion`, so the page cannot release the
  /// file before it was read
  static func inspect(
    _ recording: RoundVideoRecording,
    result: [String: Any],
    in window: UIWindow?,
    completion: @escaping () -> Void
  ) {
    guard TestHooks.isFakeRoundVideoEnabled else {
      completion()
      return
    }
    let file = MP4FileDescription.read(recording.fileURL)
    let recordedDurationMs = Int((recording.duration.seconds * 1000).rounded())
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: recording.fileURL))
    generator.appliesPreferredTrackTransform = true
    generator.generateCGImageAsynchronously(for: decodeTime) { image, _, error in
      let decodedFrame = image.map { "\($0.width)x\($0.height)" } ?? "error: \(String(describing: error))"
      DispatchQueue.main.async {
        var fileDetails = file
        fileDetails["recordedDurationMs"] = recordedDurationMs
        fileDetails["decodedFrame"] = decodedFrame
        details["file"] = fileDetails
        details["result"] = result
        record("sent", in: window)
        completion()
      }
    }
  }

  private static func show(in window: UIWindow?) {
    var report = details
    report["events"] = events
    guard JSONSerialization.isValidJSONObject(report),
          let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else {
      logger.error("Could not encode the round video report")
      return
    }
    logger.notice("Round video report: \(json, privacy: .public)")
    if let label {
      label.accessibilityValue = json
      return
    }
    guard let window else {
      return
    }
    let newLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    newLabel.text = TestHooks.roundVideoReportIdentifier
    newLabel.alpha = labelAlpha
    newLabel.isAccessibilityElement = true
    newLabel.accessibilityIdentifier = TestHooks.roundVideoReportIdentifier
    newLabel.accessibilityValue = json
    window.addSubview(newLabel)
    label = newLabel
  }
}
