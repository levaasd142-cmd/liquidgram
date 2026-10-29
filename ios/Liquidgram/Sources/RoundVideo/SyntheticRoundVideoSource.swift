import AVFoundation
import UIKit

/// Generated video and silence that stand in for the camera and the microphone in UI tests, since the simulator has
/// no camera: a moving pattern at 30 frames per second in the size of the camera's portrait frames and 48 kHz mono
/// silence, timed on the host clock like captured media. The front and the back "camera" differ in color. Only
/// `TestHooks.isFakeRoundVideoEnabled` selects it. Sample buffers are made on `queue`.
final class SyntheticRoundVideoSource: RoundVideoSource {
  private static let frameWidth = 720
  private static let frameHeight = 1280
  private static let audioFramesPerBuffer = 1024
  private static let tickInterval = DispatchTimeInterval.milliseconds(5)
  private static let frontColor = (red: 0.36, green: 0.30, blue: 0.86)
  private static let backColor = (red: 0.08, green: 0.52, blue: 0.56)
  /// The orbit of the moving dot takes this long, so consecutive frames always differ
  private static let orbitPeriod = 3.0

  let queue = DispatchQueue(label: "org.liquidgram.messenger.round-video.synthetic", qos: .userInitiated)
  var sampleBufferHandler: ((CMSampleBuffer, Bool) -> Void)?
  var eventHandler: ((RoundVideoSourceEvent) -> Void)?
  let hasAudio = true
  let canSwitchCamera = true
  let hasTorch = false
  private(set) var isFrontCamera = true

  private let displayLayer = AVSampleBufferDisplayLayer()
  // Used on `queue`
  private var timer: DispatchSourceTimer?
  private var pixelBufferPool: CVPixelBufferPool?
  private var audioFormat: CMAudioFormatDescription?
  private var startTime = CMTime.zero
  private var frameIndex: Int64 = 0
  private var audioSampleIndex: Int64 = 0
  private var isFrontPattern = true

  init() {
    displayLayer.videoGravity = .resizeAspectFill
  }

  var previewLayer: CALayer {
    displayLayer
  }

  func prepare(completion: @escaping (Result<Void, Error>) -> Void) {
    DispatchQueue.main.async {
      completion(.success(()))
    }
  }

  func start(interfaceOrientation: UIInterfaceOrientation, completion: @escaping (Result<Void, Error>) -> Void) {
    queue.async {
      self.pixelBufferPool = Self.makePixelBufferPool()
      self.audioFormat = Self.makeAudioFormat()
      self.startTime = CMClockGetTime(CMClockGetHostTimeClock())
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now(), repeating: Self.tickInterval)
      timer.setEventHandler { [weak self] in
        self?.emitDueSamples()
      }
      timer.resume()
      self.timer = timer
      DispatchQueue.main.async {
        completion(.success(()))
      }
    }
  }

  func stop(completion: (() -> Void)?) {
    queue.async {
      self.timer?.cancel()
      self.timer = nil
      DispatchQueue.main.async {
        completion?()
      }
    }
  }

  func switchCamera(completion: @escaping () -> Void) {
    isFrontCamera.toggle()
    let isFront = isFrontCamera
    queue.async {
      self.isFrontPattern = isFront
      DispatchQueue.main.async {
        completion()
      }
    }
  }

  func setTorchEnabled(_ isEnabled: Bool) {}

  private static func makePixelBufferPool() -> CVPixelBufferPool? {
    let attributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: frameWidth,
      kCVPixelBufferHeightKey as String: frameHeight,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
    ]
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
    return pool
  }

  private static func makeAudioFormat() -> CMAudioFormatDescription? {
    var description = AudioStreamBasicDescription(
      mSampleRate: Float64(RoundVideoFormat.audioSampleRate),
      mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: UInt32(MemoryLayout<Int16>.size),
      mFramesPerPacket: 1,
      mBytesPerFrame: UInt32(MemoryLayout<Int16>.size),
      mChannelsPerFrame: 1,
      mBitsPerChannel: UInt32(Int16.bitWidth),
      mReserved: 0
    )
    var format: CMAudioFormatDescription?
    let status = CMAudioFormatDescriptionCreate(
      allocator: kCFAllocatorDefault,
      asbd: &description,
      layoutSize: 0,
      layout: nil,
      magicCookieSize: 0,
      magicCookie: nil,
      extensions: nil,
      formatDescriptionOut: &format
    )
    return status == noErr ? format : nil
  }

  /// Emits every frame and every buffer of silence that is due, so the media keeps the clock's pace even when the
  /// timer fires late
  private func emitDueSamples() {
    let now = CMClockGetTime(CMClockGetHostTimeClock())
    while startTime + CMTime(value: frameIndex, timescale: RoundVideoFormat.frameRate) <= now {
      emitFrame(at: startTime + CMTime(value: frameIndex, timescale: RoundVideoFormat.frameRate))
      frameIndex += 1
    }
    let sampleRate = Int32(RoundVideoFormat.audioSampleRate)
    while startTime + CMTime(value: audioSampleIndex, timescale: sampleRate) <= now {
      emitSilence(at: startTime + CMTime(value: audioSampleIndex, timescale: sampleRate))
      audioSampleIndex += Int64(Self.audioFramesPerBuffer)
    }
  }

  private func emitFrame(at time: CMTime) {
    guard let pixelBufferPool else {
      return
    }
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer) == kCVReturnSuccess,
          let pixelBuffer else {
      return
    }
    draw(into: pixelBuffer, seconds: (time - startTime).seconds)

    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )
    guard let formatDescription else {
      return
    }
    var timing = CMSampleTimingInfo(
      duration: RoundVideoFormat.frameDuration,
      presentationTimeStamp: time,
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    guard let sampleBuffer else {
      return
    }
    sampleBufferHandler?(sampleBuffer, true)
    display(sampleBuffer)
  }

  private func emitSilence(at time: CMTime) {
    guard let audioFormat else {
      return
    }
    let byteCount = Self.audioFramesPerBuffer * MemoryLayout<Int16>.size
    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
      allocator: kCFAllocatorDefault,
      memoryBlock: nil,
      blockLength: byteCount,
      blockAllocator: kCFAllocatorDefault,
      customBlockSource: nil,
      offsetToData: 0,
      dataLength: byteCount,
      flags: kCMBlockBufferAssureMemoryNowFlag,
      blockBufferOut: &blockBuffer
    )
    guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
      return
    }
    CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: byteCount)
    var sampleBuffer: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
      allocator: kCFAllocatorDefault,
      dataBuffer: blockBuffer,
      formatDescription: audioFormat,
      sampleCount: Self.audioFramesPerBuffer,
      presentationTimeStamp: time,
      packetDescriptions: nil,
      sampleBufferOut: &sampleBuffer
    )
    if let sampleBuffer {
      sampleBufferHandler?(sampleBuffer, false)
    }
  }

  /// A colored background, a face-like disc that bobs and a dot that circles it, all inside the centre square
  private func draw(into pixelBuffer: CVPixelBuffer, seconds: Double) {
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }
    guard let context = CGContext(
      data: CVPixelBufferGetBaseAddress(pixelBuffer),
      width: Self.frameWidth,
      height: Self.frameHeight,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      return
    }
    let color = isFrontPattern ? Self.frontColor : Self.backColor
    let pulse = 0.85 + 0.15 * sin(seconds * 2)
    let background = CGColor(red: color.red * pulse, green: color.green * pulse, blue: color.blue * pulse, alpha: 1)
    context.setFillColor(background)
    context.fill(CGRect(x: 0, y: 0, width: Self.frameWidth, height: Self.frameHeight))

    let center = CGPoint(x: CGFloat(Self.frameWidth) / 2, y: CGFloat(Self.frameHeight) / 2 + 30 * sin(seconds * 3))
    context.setFillColor(CGColor(red: 1, green: 0.93, blue: 0.85, alpha: 1))
    context.fillEllipse(in: CGRect(x: center.x - 170, y: center.y - 170, width: 340, height: 340))
    context.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1))
    context.fillEllipse(in: CGRect(x: center.x - 80, y: center.y + 30, width: 40, height: 40))
    context.fillEllipse(in: CGRect(x: center.x + 40, y: center.y + 30, width: 40, height: 40))

    let angle = seconds / Self.orbitPeriod * 2 * .pi
    let dot = CGPoint(x: center.x + 260 * cos(angle), y: center.y + 260 * sin(angle))
    context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.2, alpha: 1))
    context.fillEllipse(in: CGRect(x: dot.x - 36, y: dot.y - 36, width: 72, height: 72))
  }

  /// Shows a frame in the preview at once instead of at its time stamp
  private func display(_ sampleBuffer: CMSampleBuffer) {
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
       CFArrayGetCount(attachments) > 0 {
      let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        attachment,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
      )
    }
    if #available(iOS 17.0, *) {
      displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
    } else {
      displayLayer.enqueue(sampleBuffer)
    }
  }
}
