import AVFoundation
import os
import UIKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "RoundVideo")

/// What a source tells the recorder, on the main queue
enum RoundVideoSourceEvent {
  /// The camera or the microphone went to a phone call, another app or the background
  case interrupted
  /// The device is too warm or its battery too weak to go on capturing
  case systemPressureShutdown
  case failed(Error)
}

/// Video frames and sound for the recorder: the cameras and the microphone, or generated media in UI tests
protocol RoundVideoSource: AnyObject {
  /// The serial queue on which `sampleBufferHandler` receives the sample buffers
  var queue: DispatchQueue { get }
  /// Receives every sample buffer on `queue`; the flag tells video from audio. Set it before `start`.
  var sampleBufferHandler: ((CMSampleBuffer, Bool) -> Void)? { get set }
  /// Receives events on the main queue
  var eventHandler: ((RoundVideoSourceEvent) -> Void)? { get set }
  /// Shows what the source captures, filling a square with its centre, as the round video does
  var previewLayer: CALayer { get }
  /// Whether the source delivers sound, known once `prepare` completed
  var hasAudio: Bool { get }
  var isFrontCamera: Bool { get }
  var canSwitchCamera: Bool { get }
  /// Whether the current camera has a torch for the flash; the front camera lights the face with the screen instead
  var hasTorch: Bool { get }

  /// Sets the source up; `completion` runs on the main queue
  func prepare(completion: @escaping (Result<Void, Error>) -> Void)
  /// Starts delivering sample buffers once the preview layer is on screen, upright for the interface orientation;
  /// `completion` runs on the main queue
  func start(interfaceOrientation: UIInterfaceOrientation, completion: @escaping (Result<Void, Error>) -> Void)
  /// Stops capturing and gives the audio session back; `completion` runs on the main queue
  func stop(completion: (() -> Void)?)
  /// Switches between the front and the back camera; `completion` runs on the main queue
  func switchCamera(completion: @escaping () -> Void)
  func setTorchEnabled(_ isEnabled: Bool)
}

enum RoundVideoCameraError: Error {
  case noCamera
  case cannotAddInput
  case cannotAddOutput
  case audioSessionUnavailable
}

/// The front or back camera and the microphone. Frames come out upright for the interface orientation and, from the
/// front camera, mirrored like the preview, so the round video shows what the circle showed. The session runs at 720p
/// and 30 frames per second, lower under thermal pressure.
///
/// The session uses the app's audio session, which it sets to `playAndRecord` while it runs and back to `playback`
/// afterwards. Configuration runs on `sessionQueue`, sample buffers arrive on `queue`, and the rest on the main queue.
final class RoundVideoCamera: NSObject, RoundVideoSource {
  /// Whether the device has a camera that can record, without asking for access. The simulator has none.
  static var isAvailable: Bool {
    findCamera(position: .front) != nil || findCamera(position: .back) != nil
  }

  private static let pressuredFrameRate: Int32 = 20
  private static let criticalFrameRate: Int32 = 15

  let queue = DispatchQueue(label: "org.liquidgram.messenger.round-video.samples", qos: .userInitiated)
  let canSwitchCamera = RoundVideoCamera.findCamera(position: .front) != nil
    && RoundVideoCamera.findCamera(position: .back) != nil
  var sampleBufferHandler: ((CMSampleBuffer, Bool) -> Void)?
  var eventHandler: ((RoundVideoSourceEvent) -> Void)?
  private(set) var hasAudio = false
  private(set) var isFrontCamera = true
  private(set) var hasTorch = false

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "org.liquidgram.messenger.round-video.session", qos: .userInitiated)
  private let videoPreviewLayer: AVCaptureVideoPreviewLayer
  private let videoOutput = AVCaptureVideoDataOutput()
  private let audioOutput = AVCaptureAudioDataOutput()
  /// Used on `sessionQueue`
  private var videoInput: AVCaptureDeviceInput?
  private var isTorchRequested = false
  private var isAudioSessionActive = false
  private var pressureObservation: NSKeyValueObservation?
  private var notificationObservers: [NSObjectProtocol] = []
  /// The orientation of the interface, used on the main queue before iOS 17
  private var interfaceOrientation = UIInterfaceOrientation.portrait
  /// Keeps the rotation coordinator of the current camera alive, used on the main queue
  private var rotationCoordinator: AnyObject?

  override init() {
    videoPreviewLayer = AVCaptureVideoPreviewLayer(session: session)
    super.init()
    videoPreviewLayer.videoGravity = .resizeAspectFill
  }

  deinit {
    for observer in notificationObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  var previewLayer: CALayer {
    videoPreviewLayer
  }

  func prepare(completion: @escaping (Result<Void, Error>) -> Void) {
    observeSession()
    sessionQueue.async {
      let result = Result { try self.configureSession() }
      DispatchQueue.main.async {
        if case .success = result {
          self.observeSystemPressure()
        }
        completion(result)
      }
    }
  }

  func start(interfaceOrientation: UIInterfaceOrientation, completion: @escaping (Result<Void, Error>) -> Void) {
    self.interfaceOrientation = interfaceOrientation
    // The rotation that keeps the preview upright needs the preview layer on screen
    let rotation = videoInput.map { makeRotation(for: $0.device) }
    if let rotation {
      applyPreviewRotation(rotation)
    }
    sessionQueue.async {
      if let rotation {
        self.session.beginConfiguration()
        self.applyOutputRotation(rotation)
        self.session.commitConfiguration()
      }
      let result: Result<Void, Error>
      if self.hasAudio && !self.activateAudioSession() {
        result = .failure(RoundVideoCameraError.audioSessionUnavailable)
      } else {
        self.session.startRunning()
        result = .success(())
      }
      DispatchQueue.main.async {
        completion(result)
      }
    }
  }

  func stop(completion: (() -> Void)?) {
    pressureObservation = nil
    sessionQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
      }
      self.deactivateAudioSession()
      DispatchQueue.main.async {
        completion?()
      }
    }
  }

  func switchCamera(completion: @escaping () -> Void) {
    let position: AVCaptureDevice.Position = isFrontCamera ? .back : .front
    guard let device = Self.findCamera(position: position) else {
      completion()
      return
    }
    // The new camera turns in the same configuration that adds it, so no frame comes out sideways
    let rotation = makeRotation(for: device)
    pressureObservation = nil
    sessionQueue.async {
      let previousInput = self.videoInput
      Self.turnTorchOff(previousInput?.device)
      self.session.beginConfiguration()
      if let previousInput {
        self.session.removeInput(previousInput)
      }
      do {
        let input = try AVCaptureDeviceInput(device: device)
        guard self.session.canAddInput(input) else {
          throw RoundVideoCameraError.cannotAddInput
        }
        self.session.addInput(input)
        self.videoInput = input
      } catch {
        logger.error("Could not switch the camera: \(String(describing: error), privacy: .public)")
        if let previousInput, self.session.canAddInput(previousInput) {
          self.session.addInput(previousInput)
        }
      }
      self.configureVideoConnection()
      self.applyOutputRotation(rotation)
      self.session.commitConfiguration()
      let currentDevice = self.videoInput?.device
      Self.limitFrameRate(of: currentDevice, to: RoundVideoFormat.frameRate)
      self.applyTorch()
      let isFront = currentDevice?.position != .back
      let hasTorch = currentDevice.map { $0.hasTorch && $0.isTorchModeSupported(.on) } ?? false

      DispatchQueue.main.async {
        self.isFrontCamera = isFront
        self.hasTorch = hasTorch
        if let currentDevice, currentDevice != device {
          // Switching failed, so the previous camera keeps its rotation
          self.applyPreviewRotation(self.makeRotation(for: currentDevice))
        } else {
          self.applyPreviewRotation(rotation)
        }
        self.observeSystemPressure()
        completion()
      }
    }
  }

  func setTorchEnabled(_ isEnabled: Bool) {
    sessionQueue.async {
      self.isTorchRequested = isEnabled
      self.applyTorch()
    }
  }

  private static func findCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
  }

  /// At most `frameRate` frames per second, where the active format allows it
  private static func limitFrameRate(of device: AVCaptureDevice?, to frameRate: Int32) {
    guard let device else {
      return
    }
    let isSupported = device.activeFormat.videoSupportedFrameRateRanges.contains { range in
      range.minFrameRate <= Double(frameRate) && Double(frameRate) <= range.maxFrameRate
    }
    guard isSupported else {
      return
    }
    do {
      try device.lockForConfiguration()
      let frameDuration = CMTime(value: 1, timescale: frameRate)
      device.activeVideoMinFrameDuration = frameDuration
      device.activeVideoMaxFrameDuration = frameDuration
      device.unlockForConfiguration()
    } catch {
      logger.error("Could not set the frame rate: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Runs on `sessionQueue`
  private func configureSession() throws {
    guard let device = Self.findCamera(position: .front) ?? Self.findCamera(position: .back) else {
      throw RoundVideoCameraError.noCamera
    }
    session.beginConfiguration()
    defer {
      session.commitConfiguration()
    }
    // The app sets the audio session itself, so the session does not switch it behind the page's back
    session.automaticallyConfiguresApplicationAudioSession = false
    if session.canSetSessionPreset(.hd1280x720) {
      session.sessionPreset = .hd1280x720
    }

    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      throw RoundVideoCameraError.cannotAddInput
    }
    session.addInput(input)
    videoInput = input

    // Without a microphone the video has no sound, which Telegram accepts
    if let microphone = AVCaptureDevice.default(for: .audio),
       let microphoneInput = try? AVCaptureDeviceInput(device: microphone),
       session.canAddInput(microphoneInput) {
      session.addInput(microphoneInput)
      hasAudio = true
    }

    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
    ]
    videoOutput.alwaysDiscardsLateVideoFrames = true
    videoOutput.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddOutput(videoOutput) else {
      throw RoundVideoCameraError.cannotAddOutput
    }
    session.addOutput(videoOutput)
    if hasAudio {
      audioOutput.setSampleBufferDelegate(self, queue: queue)
      if session.canAddOutput(audioOutput) {
        session.addOutput(audioOutput)
      } else {
        hasAudio = false
      }
    }
    configureVideoConnection()
    Self.limitFrameRate(of: device, to: RoundVideoFormat.frameRate)
    isFrontCamera = device.position != .back
    hasTorch = device.hasTorch && device.isTorchModeSupported(.on)
  }

  /// Mirrors the front camera like the preview. Runs on `sessionQueue` inside a configuration.
  private func configureVideoConnection() {
    guard let connection = videoOutput.connection(with: .video) else {
      return
    }
    if connection.isVideoMirroringSupported {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = videoInput?.device.position != .back
    }
  }

  /// The rotation of a camera's frames that matches the interface: an angle from the rotation coordinator on iOS 17
  /// and later, which knows how each camera is mounted, and an orientation before. Runs on the main queue.
  private func makeRotation(for device: AVCaptureDevice) -> CameraRotation {
    if #available(iOS 17.0, *) {
      let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
      rotationCoordinator = coordinator
      return .angle(coordinator.videoRotationAngleForHorizonLevelPreview)
    }
    return .orientation(Self.makeVideoOrientation(interfaceOrientation))
  }

  private static func makeVideoOrientation(
    _ interfaceOrientation: UIInterfaceOrientation
  ) -> AVCaptureVideoOrientation {
    switch interfaceOrientation {
    case .portraitUpsideDown:
      return .portraitUpsideDown
    case .landscapeLeft:
      return .landscapeLeft
    case .landscapeRight:
      return .landscapeRight
    case .portrait, .unknown:
      return .portrait
    @unknown default:
      return .portrait
    }
  }

  private func applyPreviewRotation(_ rotation: CameraRotation) {
    guard let connection = videoPreviewLayer.connection else {
      return
    }
    rotation.apply(to: connection)
  }

  /// Turns the frames physically, which takes a while, so it happens inside a configuration before the frames of a
  /// camera flow. Runs on `sessionQueue`.
  private func applyOutputRotation(_ rotation: CameraRotation) {
    guard let connection = videoOutput.connection(with: .video) else {
      return
    }
    rotation.apply(to: connection)
  }

  private static func turnTorchOff(_ device: AVCaptureDevice?) {
    guard let device, device.hasTorch, device.torchMode != .off else {
      return
    }
    do {
      try device.lockForConfiguration()
      device.torchMode = .off
      device.unlockForConfiguration()
    } catch {
      logger.error("Could not turn the torch off: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Runs on `sessionQueue`
  private func applyTorch() {
    guard let device = videoInput?.device, device.hasTorch else {
      return
    }
    let mode: AVCaptureDevice.TorchMode = isTorchRequested ? .on : .off
    guard device.isTorchModeSupported(mode), device.torchMode != mode else {
      return
    }
    do {
      try device.lockForConfiguration()
      device.torchMode = mode
      device.unlockForConfiguration()
    } catch {
      logger.error("Could not switch the torch: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// The page's own audio plays in WebKit's processes; this session only records. Runs on `sessionQueue`.
  private func activateAudioSession() -> Bool {
    let audioSession = AVAudioSession.sharedInstance()
    var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
    #if compiler(>=6.2)
    options.insert(.allowBluetoothHFP)
    #else
    options.insert(.allowBluetooth)
    #endif
    do {
      try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: options)
      try audioSession.setActive(true)
      isAudioSessionActive = true
      return true
    } catch {
      logger.error("Could not activate the audio session: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  /// Lets other apps' audio resume and restores the category that `AppDelegate` sets. Runs on `sessionQueue`.
  private func deactivateAudioSession() {
    guard isAudioSessionActive else {
      return
    }
    isAudioSessionActive = false
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      logger.error("Could not deactivate the audio session: \(error.localizedDescription, privacy: .public)")
    }
    do {
      try audioSession.setCategory(.playback, mode: .default, options: [])
    } catch {
      logger.error("Could not restore the audio session: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func observeSession() {
    guard notificationObservers.isEmpty else {
      return
    }
    let center = NotificationCenter.default
    notificationObservers = [
      center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) {
        [weak self] notification in
        let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
        logger.info("The capture session was interrupted, reason \(reason ?? 0, privacy: .public)")
        self?.eventHandler?(.interrupted)
      },
      center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) {
        [weak self] notification in
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
        logger.error("The capture session failed: \(String(describing: error), privacy: .public)")
        self?.eventHandler?(.failed(error ?? RoundVideoError.writingFailed))
      },
    ]
  }

  /// Lowers the frame rate as the device warms up, as Apple recommends, and stops at the shutdown level, where the
  /// camera stops delivering frames anyway. Runs on the main queue.
  private func observeSystemPressure() {
    guard let device = videoInput?.device else {
      return
    }
    pressureObservation = device.observe(\.systemPressureState, options: [.initial, .new]) {
      [weak self] device, _ in
      let level = device.systemPressureState.level
      let frameRate: Int32
      switch level {
      case .serious:
        frameRate = Self.pressuredFrameRate
      case .critical:
        frameRate = Self.criticalFrameRate
      case .shutdown:
        DispatchQueue.main.async {
          self?.eventHandler?(.systemPressureShutdown)
        }
        return
      default:
        frameRate = RoundVideoFormat.frameRate
      }
      self?.sessionQueue.async {
        logger.info("System pressure \(level.rawValue, privacy: .public): \(frameRate, privacy: .public) fps")
        Self.limitFrameRate(of: device, to: frameRate)
      }
    }
  }
}

extension RoundVideoCamera: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    sampleBufferHandler?(sampleBuffer, output === videoOutput)
  }
}

/// How the camera's frames turn to match the interface
private enum CameraRotation {
  case angle(CGFloat)
  case orientation(AVCaptureVideoOrientation)

  func apply(to connection: AVCaptureConnection) {
    switch self {
    case .angle(let angle):
      if #available(iOS 17.0, *), connection.isVideoRotationAngleSupported(angle) {
        connection.videoRotationAngle = angle
      }
    case .orientation(let orientation):
      if connection.isVideoOrientationSupported {
        connection.videoOrientation = orientation
      }
    }
  }
}
