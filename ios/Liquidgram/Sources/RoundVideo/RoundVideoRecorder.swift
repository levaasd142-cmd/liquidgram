import AVFoundation
import os
import UIKit
import WebKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "RoundVideo")

/// Records round videos (кружки) for the page and hands the files over through `MediaStore`. The page asks with
/// `{ type: 'recordRoundVideo', requestId, canSendOneTimeMedia }`; the recorder covers the page until the user sends
/// or cancels, and the page gets `{ url, durationMs, width, height, isViewOnce }`, or `nil` for nothing to send. One
/// recorder at a time: a request while one is up gets `nil` at once. Used on the main queue.
final class RoundVideoRecorder {
  typealias Completion = ([String: Any]?) -> Void

  private var isRecording = false
  private weak var controller: RoundVideoRecorderViewController?

  /// Shows the recorder over the page of `webView` and calls `completion` once with the page's answer
  func record(canSendOneTimeMedia: Bool, from webView: WKWebView?, completion: @escaping Completion) {
    guard !isRecording, let window = webView?.window, let presenter = Self.findPresenter(in: window) else {
      logger.info("Ignored a request to record a round video while one is recorded or the page is hidden")
      completion(nil)
      return
    }
    isRecording = true
    let source: RoundVideoSource?
    if TestHooks.isFakeRoundVideoEnabled {
      source = SyntheticRoundVideoSource()
    } else {
      source = RoundVideoCamera.isAvailable ? RoundVideoCamera() : nil
    }
    let controller = RoundVideoRecorderViewController(
      source: source,
      canSendOneTimeMedia: canSendOneTimeMedia,
      interfaceOrientation: window.windowScene?.interfaceOrientation ?? .portrait
    ) { [weak self, weak window] outcome in
      self?.isRecording = false
      Self.publish(outcome, in: window, completion: completion)
    }
    self.controller = controller
    // The keyboard would stay above the recorder
    window.endEditing(true)
    presenter.present(controller, animated: true)
    // UIKit drops a presentation that comes during another one, and the page would wait for an answer forever
    DispatchQueue.main.async { [weak controller] in
      guard let controller, controller.presentingViewController == nil, !controller.isBeingPresented else {
        return
      }
      logger.error("Could not show the round video recorder")
      controller.cancelRecording(reason: "notPresented")
    }
    RoundVideoTestReport.record("presented", in: window)
  }

  /// Closes the recorder without an answer, for a page that is gone
  func cancel() {
    controller?.cancelRecording(reason: "pageGone")
  }

  /// The page fetched the file at `path` and no longer needs it
  func releaseMedia(path: String, in window: UIWindow?) {
    MediaStore.shared.release(path: path)
    RoundVideoTestReport.record("released", in: window)
  }

  private static func findPresenter(in window: UIWindow) -> UIViewController? {
    guard var presenter = window.rootViewController else {
      return nil
    }
    while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
      presenter = presented
    }
    return presenter
  }

  /// Registers a recording for the page, or reports that there is nothing to send
  private static func publish(
    _ outcome: RoundVideoRecorderOutcome,
    in window: UIWindow?,
    completion: @escaping Completion
  ) {
    switch outcome {
    case .recorded(let recording, let isViewOnce):
      guard recording.duration >= RoundVideoFormat.minDuration,
            let path = MediaStore.shared.register(recording.fileURL, contentType: RoundVideoFormat.contentType) else {
        logger.error("Dropped a round video that is too short or unreadable")
        try? FileManager.default.removeItem(at: recording.fileURL)
        RoundVideoTestReport.record("dropped", in: window)
        completion(nil)
        return
      }
      let result: [String: Any] = [
        "url": path,
        "durationMs": Int((recording.duration.seconds * 1000).rounded()),
        "width": recording.dimension,
        "height": recording.dimension,
        "isViewOnce": isViewOnce,
      ]
      logger.info("Recorded a round video of \(recording.duration.seconds, privacy: .public) s")
      RoundVideoTestReport.inspect(recording, result: result, in: window) {
        completion(result)
      }
    case .closed(let reason):
      logger.info("The round video recorder closed: \(reason, privacy: .public)")
      RoundVideoTestReport.record(reason, in: window)
      completion(nil)
    }
  }
}
