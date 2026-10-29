import AVFoundation
import CoreImage
import os

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "RoundVideo")

/// The format of round video messages as Telegram's own apps record them: a square H.264 High profile video with
/// CABAC at about 1 Mbit/s and mono AAC at 64 kbit/s and 48 kHz, in an MP4 whose movie header comes first, so it can
/// play while it downloads. Recording stops at 59.5 seconds, and clips shorter than a second are dropped.
enum RoundVideoFormat {
  static let dimension = 480
  static let frameRate: Int32 = 30
  static let videoBitRate = 1_000_000
  static let audioBitRate = 64_000
  static let audioSampleRate = 48_000
  static let audioChannelCount = 1
  static let maxDuration = CMTime(value: 595, timescale: 10)
  static let minDuration = CMTime(value: 1, timescale: 1)
  static let frameDuration = CMTime(value: 1, timescale: frameRate)
  static let fileExtension = "mp4"
  static let contentType = "video/mp4"
  /// Seconds between key frames, so a player can start and seek quickly
  static let keyFrameInterval = 1
}

enum RoundVideoError: Error {
  case unsupportedSettings
  case writingFailed
  case noFrames
}

/// A finished round video file
struct RoundVideoRecording {
  let fileURL: URL
  let duration: CMTime
  let dimension: Int
}

/// Writes a round video from camera frames and microphone sound: each frame's centre square is scaled to the round
/// video size, and the sound is encoded as AAC. The first video frame starts the recording, and frames past the
/// duration limit end it. Used on the source's sample buffer queue only; `finish` calls back on another queue.
final class RoundVideoWriter {
  enum VideoResult {
    /// The frame started the recording
    case started
    case appended
    /// The encoder was busy or the frame came out of order
    case dropped
    /// The frame lies past the duration limit, so the recording is complete and waits for `finish`
    case limitReached
    /// The writer is not recording, for example after `finish` or the limit
    case ignored
    case failed
  }

  private enum State {
    case idle
    case waitingForFirstFrame
    case recording
    case limitReached
    case finishing
    case cancelled
    case failed
  }

  let outputURL: URL

  private let writer: AVAssetWriter
  private let videoInput: AVAssetWriterInput
  private let audioInput: AVAssetWriterInput?
  private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
  /// Scales the frames on the GPU; intermediate images are not cached, since every frame is new
  private let ciContext = CIContext(options: [.cacheIntermediates: false])
  private var state = State.idle
  private var startTime: CMTime?
  private var lastVideoTime: CMTime?

  init(outputURL: URL, hasAudio: Bool) throws {
    self.outputURL = outputURL
    writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
    // The movie header goes before the media data, as `supportsStreaming` in the message attributes promises
    writer.shouldOptimizeForNetworkUse = true

    let videoSettings = Self.makeVideoSettings()
    guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
      throw RoundVideoError.unsupportedSettings
    }
    videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = true
    pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: videoInput,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: RoundVideoFormat.dimension,
        kCVPixelBufferHeightKey as String: RoundVideoFormat.dimension,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      ]
    )
    guard writer.canAdd(videoInput) else {
      throw RoundVideoError.unsupportedSettings
    }
    writer.add(videoInput)

    if hasAudio {
      let audioSettings = Self.makeAudioSettings()
      guard writer.canApply(outputSettings: audioSettings, forMediaType: .audio) else {
        throw RoundVideoError.unsupportedSettings
      }
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      input.expectsMediaDataInRealTime = true
      guard writer.canAdd(input) else {
        throw RoundVideoError.unsupportedSettings
      }
      writer.add(input)
      audioInput = input
    } else {
      audioInput = nil
    }
  }

  /// Opens the file, so the first frame only starts the session
  func start() {
    guard state == .idle else {
      return
    }
    if writer.startWriting() {
      state = .waitingForFirstFrame
    } else {
      state = .failed
      logger.error("Could not start writing: \(Self.describe(self.writer.error), privacy: .public)")
    }
  }

  func appendVideo(_ sampleBuffer: CMSampleBuffer) -> VideoResult {
    guard state == .waitingForFirstFrame || state == .recording else {
      return .ignored
    }
    guard writer.status == .writing else {
      return fail()
    }
    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard time.isValid, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return .dropped
    }

    var result = VideoResult.appended
    if let startTime {
      if time - startTime >= RoundVideoFormat.maxDuration {
        state = .limitReached
        return .limitReached
      }
      // A camera switch can deliver a late frame of the previous camera
      if let lastVideoTime, time <= lastVideoTime {
        return .dropped
      }
    } else {
      writer.startSession(atSourceTime: time)
      startTime = time
      state = .recording
      result = .started
    }

    guard videoInput.isReadyForMoreMediaData, let pool = pixelBufferAdaptor.pixelBufferPool else {
      return result == .started ? result : .dropped
    }
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
          let pixelBuffer else {
      return result == .started ? result : .dropped
    }
    ciContext.render(Self.makeSquareImage(from: imageBuffer), to: pixelBuffer)
    guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: time) else {
      return writer.status == .failed ? fail() : .dropped
    }
    lastVideoTime = time
    return result
  }

  func appendAudio(_ sampleBuffer: CMSampleBuffer) {
    guard state == .recording, let audioInput, let startTime else {
      return
    }
    let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    // Sound from before the first frame or past the limit is not part of the video
    guard time.isValid, time >= startTime, time - startTime < RoundVideoFormat.maxDuration,
          audioInput.isReadyForMoreMediaData else {
      return
    }
    if !audioInput.append(sampleBuffer), writer.status == .failed {
      _ = fail()
    }
  }

  /// Ends the video one frame after its last frame and closes the file. `completion` runs once, on a queue of the
  /// writer. A writer that has no frame deletes its file and fails.
  func finish(completion: @escaping (Result<RoundVideoRecording, Error>) -> Void) {
    guard state == .recording || state == .limitReached, let startTime, let lastVideoTime,
          writer.status == .writing else {
      let error = writer.error ?? RoundVideoError.noFrames
      cancel()
      completion(.failure(error))
      return
    }
    state = .finishing
    let endTime = lastVideoTime + RoundVideoFormat.frameDuration
    let duration = endTime - startTime
    videoInput.markAsFinished()
    audioInput?.markAsFinished()
    writer.endSession(atSourceTime: endTime)
    let writer = writer
    let outputURL = outputURL
    writer.finishWriting {
      guard writer.status == .completed else {
        logger.error("Could not finish the video: \(Self.describe(writer.error), privacy: .public)")
        try? FileManager.default.removeItem(at: outputURL)
        completion(.failure(writer.error ?? RoundVideoError.writingFailed))
        return
      }
      completion(.success(RoundVideoRecording(
        fileURL: outputURL,
        duration: duration,
        dimension: RoundVideoFormat.dimension
      )))
    }
  }

  /// Stops writing and deletes the file. A writer that is finishing completes instead.
  func cancel() {
    switch state {
    case .finishing, .cancelled:
      return
    case .idle, .waitingForFirstFrame, .recording, .limitReached, .failed:
      if writer.status == .writing {
        writer.cancelWriting()
      }
      state = .cancelled
      try? FileManager.default.removeItem(at: outputURL)
    }
  }

  /// Frees the memory that Core Image keeps between frames
  func clearCaches() {
    ciContext.clearCaches()
  }

  private static func makeVideoSettings() -> [String: Any] {
    [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: RoundVideoFormat.dimension,
      AVVideoHeightKey: RoundVideoFormat.dimension,
      // Telegram's players show the colors of other clients' round videos the same way
      AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
      ],
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: RoundVideoFormat.videoBitRate,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
        AVVideoExpectedSourceFrameRateKey: RoundVideoFormat.frameRate,
        AVVideoMaxKeyFrameIntervalDurationKey: RoundVideoFormat.keyFrameInterval,
        // Frame reordering adds latency that a real-time source cannot afford
        AVVideoAllowFrameReorderingKey: false,
      ] as [String: Any],
    ]
  }

  private static func makeAudioSettings() -> [String: Any] {
    [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: RoundVideoFormat.audioSampleRate,
      AVNumberOfChannelsKey: RoundVideoFormat.audioChannelCount,
      AVEncoderBitRateKey: RoundVideoFormat.audioBitRate,
    ]
  }

  /// The centre square of a frame, scaled to the round video size. The circle of the recorder shows the same square.
  private static func makeSquareImage(from imageBuffer: CVImageBuffer) -> CIImage {
    let image = CIImage(cvImageBuffer: imageBuffer)
    let extent = image.extent
    let side = min(extent.width, extent.height)
    let square = CGRect(x: extent.midX - side / 2, y: extent.midY - side / 2, width: side, height: side)
    let scale = CGFloat(RoundVideoFormat.dimension) / side
    return image
      .cropped(to: square)
      .transformed(by: CGAffineTransform(translationX: -square.minX, y: -square.minY))
      .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
  }

  private static func describe(_ error: Error?) -> String {
    error.map { String(describing: $0) } ?? "unknown error"
  }

  private func fail() -> VideoResult {
    logger.error("The video writer failed: \(Self.describe(self.writer.error), privacy: .public)")
    state = .failed
    return .failed
  }
}
