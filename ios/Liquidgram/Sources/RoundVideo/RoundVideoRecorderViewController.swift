import AVFoundation
import os
import UIKit

private let logger = Logger(subsystem: "org.liquidgram.messenger", category: "RoundVideo")

private enum Strings {
  static let cancel = NSLocalizedString(
    "roundVideo.cancel",
    tableName: "RoundVideo",
    value: "Cancel",
    comment: "Button that discards the round video being recorded"
  )
  static let send = NSLocalizedString(
    "roundVideo.send",
    tableName: "RoundVideo",
    value: "Send video message",
    comment: "Accessibility label of the button that stops recording and sends the round video"
  )
  static let switchCamera = NSLocalizedString(
    "roundVideo.switchCamera",
    tableName: "RoundVideo",
    value: "Switch camera",
    comment: "Accessibility label of the button that switches between the front and the back camera"
  )
  static let flash = NSLocalizedString(
    "roundVideo.flash",
    tableName: "RoundVideo",
    value: "Flash",
    comment: "Accessibility label of the button that lights the face with the screen or turns the torch on"
  )
  static let viewOnce = NSLocalizedString(
    "roundVideo.viewOnce",
    tableName: "RoundVideo",
    value: "View once",
    comment: "Accessibility label of the button that makes the round video disappear after it was watched"
  )
  static let on = NSLocalizedString(
    "roundVideo.on",
    tableName: "RoundVideo",
    value: "On",
    comment: "Accessibility value of a switched-on button of the round video recorder"
  )
  static let off = NSLocalizedString(
    "roundVideo.off",
    tableName: "RoundVideo",
    value: "Off",
    comment: "Accessibility value of a switched-off button of the round video recorder"
  )
  static let recordingTime = NSLocalizedString(
    "roundVideo.recordingTime",
    tableName: "RoundVideo",
    value: "Recording time",
    comment: "Accessibility label of the round video recorder's timer"
  )
  static let close = NSLocalizedString(
    "roundVideo.close",
    tableName: "RoundVideo",
    value: "Close",
    comment: "Button that closes the round video recorder when it cannot record"
  )
  static let openSettings = NSLocalizedString(
    "roundVideo.openSettings",
    tableName: "RoundVideo",
    value: "Open Settings",
    comment: "Button that opens the app's page in the Settings app to allow the camera and the microphone"
  )
  static let accessDeniedTitle = NSLocalizedString(
    "roundVideo.accessDenied.title",
    tableName: "RoundVideo",
    value: "Allow the camera and the microphone",
    comment: "Title shown when the app may not use the camera or the microphone"
  )
  static let accessDeniedMessage = NSLocalizedString(
    "roundVideo.accessDenied.message",
    tableName: "RoundVideo",
    value: "Liquidgram needs the camera and the microphone to record video messages. You can allow them in Settings.",
    comment: "Explains how to allow the camera and the microphone"
  )
  static let noCameraTitle = NSLocalizedString(
    "roundVideo.noCamera.title",
    tableName: "RoundVideo",
    value: "No camera",
    comment: "Title shown on a device without a camera, such as the simulator"
  )
  static let noCameraMessage = NSLocalizedString(
    "roundVideo.noCamera.message",
    tableName: "RoundVideo",
    value: "This device has no camera that can record video messages.",
    comment: "Shown on a device without a camera, such as the simulator"
  )
  static let busyTitle = NSLocalizedString(
    "roundVideo.busy.title",
    tableName: "RoundVideo",
    value: "The camera is busy",
    comment: "Title shown when a call or another app holds the camera or the microphone"
  )
  static let busyMessage = NSLocalizedString(
    "roundVideo.busy.message",
    tableName: "RoundVideo",
    value: "A call or another app is using the camera or the microphone. Try again when it is done.",
    comment: "Shown when a call or another app holds the camera or the microphone"
  )
  static let tooWarmTitle = NSLocalizedString(
    "roundVideo.tooWarm.title",
    tableName: "RoundVideo",
    value: "Your device is too warm",
    comment: "Title shown when the device is too hot to record video"
  )
  static let tooWarmMessage = NSLocalizedString(
    "roundVideo.tooWarm.message",
    tableName: "RoundVideo",
    value: "Let it cool down, then record your video message again.",
    comment: "Shown when the device is too hot to record video"
  )
  static let failedTitle = NSLocalizedString(
    "roundVideo.failed.title",
    tableName: "RoundVideo",
    value: "Could not record",
    comment: "Title shown when recording a round video failed"
  )
  static let failedMessage = NSLocalizedString(
    "roundVideo.failed.message",
    tableName: "RoundVideo",
    value: "Something went wrong while recording the video message. Try again.",
    comment: "Shown when recording a round video failed"
  )
}

/// How the recorder closed
enum RoundVideoRecorderOutcome {
  /// A recording to send, at least as long as the minimum
  case recorded(RoundVideoRecording, isViewOnce: Bool)
  /// Nothing to send; the reason goes to the log and the UI tests' report
  case closed(reason: String)
}

/// The round video recorder, like Telegram's: a dimmed full-screen overlay with a circular live preview and a ring
/// around it that fills up to the duration limit, the elapsed time with a blinking dot, Cancel, a send button that
/// stops and sends, and buttons that switch the camera, turn the flash on (the screen lights the face for the front
/// camera, the torch for the back one) and make the video view-once when the chat allows it.
///
/// Recording starts with the first frame, without another tap, since the page opened the recorder from its record
/// button. The limit, a call, the app going to the background or overheating stop it: a clip of a second or more
/// stays and loops in the circle until Send or Cancel, a shorter one is discarded and the recorder closes. Without a
/// camera, without access or with a busy camera, the recorder explains it instead. It is portrait on iPhone and keeps
/// the orientation it opened in on iPad. `completion` runs once, after the recorder was dismissed.
final class RoundVideoRecorderViewController: UIViewController {
  /// Accessibility identifiers for VoiceOver and the UI tests
  enum Identifier {
    static let recorder = "liquidgram.roundVideo.recorder"
    static let preview = "liquidgram.roundVideo.preview"
    static let timer = "liquidgram.roundVideo.timer"
    static let send = "liquidgram.roundVideo.send"
    static let cancel = "liquidgram.roundVideo.cancel"
    static let flip = "liquidgram.roundVideo.flip"
    static let flash = "liquidgram.roundVideo.flash"
    static let viewOnce = "liquidgram.roundVideo.viewOnce"
    static let message = "liquidgram.roundVideo.message"
    static let settings = "liquidgram.roundVideo.settings"
    static let close = "liquidgram.roundVideo.close"
  }

  private enum Phase {
    /// Asking for access and starting the source; recording starts with the first frame
    case preparing
    case recording(startTime: CFTimeInterval)
    /// Closing the file, before sending it or showing it
    case finishing
    /// The limit or an interruption ended the recording, which waits for Send or Cancel
    case stopped(RoundVideoRecording)
    case message
    case closed
  }

  private enum Message {
    case accessDenied
    case noCamera
    case busy
    case tooWarm
    case failed

    var reason: String {
      switch self {
      case .accessDenied:
        return "accessDenied"
      case .noCamera:
        return "noCamera"
      case .busy:
        return "busy"
      case .tooWarm:
        return "tooWarm"
      case .failed:
        return "failed"
      }
    }
  }

  private static let previewWidthRatio: CGFloat = 0.78
  /// The least room between the circle and the edges of the area above the buttons
  private static let previewMargin: CGFloat = 40
  private static let ringOutset: CGFloat = 8
  private static let ringWidth: CGFloat = 4
  private static let sendButtonSize: CGFloat = 64
  private static let smallButtonSize: CGFloat = 44
  private static let sideInset: CGFloat = 20
  private static let timerInset: CGFloat = 24
  private static let bottomInset: CGFloat = 16
  private static let rowSpacing: CGFloat = 20
  private static let buttonSpacing: CGFloat = 12
  private static let messageInset: CGFloat = 24
  private static let messageSpacing: CGFloat = 12
  private static let dotSize: CGFloat = 10
  private static let dotSpacing: CGFloat = 8
  private static let iconPointSize: CGFloat = 18
  private static let sendIconPointSize: CGFloat = 24
  private static let messageIconPointSize: CGFloat = 44
  private static let timerFontSize: CGFloat = 17
  private static let dimAlpha: CGFloat = 0.5
  private static let disabledAlpha: CGFloat = 0.4
  private static let buttonBackgroundAlpha: CGFloat = 0.18
  private static let messageTextAlpha: CGFloat = 0.8
  /// A warm white that lights the face for the front camera, like Telegram's
  private static let flashColor = UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
  /// The controls' color over the screen flash, where white would not show
  private static let flashForegroundColor = UIColor(white: 0.1, alpha: 1)
  /// The web app's accent color
  private static let accentColor = UIColor(red: 0x33 / 255, green: 0x90 / 255, blue: 0xEC / 255, alpha: 1)
  /// The red dot pulses once in this time; the display link drives it, since XCUITest waits for endless animations
  private static let pulsePeriod: CFTimeInterval = 1.2
  private static let pulseMinimumAlpha: CGFloat = 0.2
  private static let flipInterval: CFTimeInterval = 1
  private static let flipAnimationDuration: TimeInterval = 0.35
  private static let flashAnimationDuration: TimeInterval = 0.2
  private static let displayLinkFrameRate: Float = 30
  private static let secondsPerMinute = 60
  private static let spokenDurationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = .full
    return formatter
  }()

  private let source: RoundVideoSource?
  private let canSendOneTimeMedia: Bool
  /// The interface orientation when the recorder opened, which it keeps
  private let recordingOrientation: UIInterfaceOrientation
  private let completion: (RoundVideoRecorderOutcome) -> Void

  private var phase = Phase.preparing
  /// Used on the source's queue once created
  private var writer: RoundVideoWriter?
  private var isPrepared = false
  private var isVisible = false
  private var isStarting = false
  private var isViewOnce = false
  private var isFlashOn = false
  private var isSwitchingCamera = false
  private var lastFlipTime: CFTimeInterval = 0
  private var initialBrightness: CGFloat?
  /// The idle timer's setting before the recorder turned it off, `nil` while it did not
  private var previousIdleTimerSetting: Bool?
  private var displayLink: CADisplayLink?
  private var notificationObservers: [NSObjectProtocol] = []
  private var player: AVQueuePlayer?
  private var playerLooper: AVPlayerLooper?
  private var playerLayer: AVPlayerLayer?
  private var backgroundTask = UIBackgroundTaskIdentifier.invalid

  private let dimView = UIView()
  private let flashView = UIView()
  private let previewView = UIView()
  private let ringView = RecorderRingView(lineWidth: RoundVideoRecorderViewController.ringWidth)
  private let spinner = UIActivityIndicatorView(style: .large)
  private let recordingDot = UIView()
  private let timerLabel = UILabel()
  private let timerView = UIStackView()
  private let messageView = UIStackView()
  private let messageIconView = UIImageView()
  private let messageTitleLabel = UILabel()
  private let messageTextLabel = UILabel()
  private lazy var cancelButton = makeTextButton(title: Strings.cancel, identifier: Identifier.cancel) { [weak self] in
    self?.cancel()
  }
  private lazy var sendButton = makeSendButton()
  private lazy var flipButton = makeRoundButton(
    symbolName: "arrow.triangle.2.circlepath.camera",
    identifier: Identifier.flip,
    label: Strings.switchCamera
  ) { [weak self] in
    self?.switchCamera()
  }
  private lazy var flashButton = makeRoundButton(
    symbolName: "bolt.slash.fill",
    identifier: Identifier.flash,
    label: Strings.flash
  ) { [weak self] in
    self?.toggleFlash()
  }
  private lazy var viewOnceButton = makeRoundButton(
    symbolName: "1.circle",
    identifier: Identifier.viewOnce,
    label: Strings.viewOnce
  ) { [weak self] in
    self?.toggleViewOnce()
  }
  private lazy var settingsButton = makeTextButton(
    title: Strings.openSettings,
    identifier: Identifier.settings
  ) { [weak self] in
    self?.openSettings()
  }
  private lazy var closeButton = makeTextButton(title: Strings.close, identifier: Identifier.close) { [weak self] in
    self?.close(.closed(reason: self?.messageReason ?? "closed"))
  }
  private var messageReason: String?

  /// `source` is `nil` on a device without a camera
  init(
    source: RoundVideoSource?,
    canSendOneTimeMedia: Bool,
    interfaceOrientation: UIInterfaceOrientation,
    completion: @escaping (RoundVideoRecorderOutcome) -> Void
  ) {
    self.source = source
    self.canSendOneTimeMedia = canSendOneTimeMedia
    recordingOrientation = interfaceOrientation
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
    modalPresentationCapturesStatusBarAppearance = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    for observer in notificationObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    displayLink?.invalidate()
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    isScreenFlashVisible ? .darkContent : .lightContent
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    guard traitCollection.userInterfaceIdiom == .pad else {
      return .portrait
    }
    // The recording keeps one orientation from start to end
    switch recordingOrientation {
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

  override func loadView() {
    let rootView = UIView()
    rootView.backgroundColor = .clear
    // The controls are light on the dimmed chat in either theme
    rootView.overrideUserInterfaceStyle = .dark
    rootView.accessibilityIdentifier = Identifier.recorder
    // VoiceOver stays in the recorder instead of reaching the chat behind it
    rootView.accessibilityViewIsModal = true

    let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    dimView.backgroundColor = UIColor.black.withAlphaComponent(Self.dimAlpha)
    flashView.backgroundColor = Self.flashColor
    flashView.alpha = 0
    for backgroundView in [blurView, dimView, flashView] {
      backgroundView.frame = rootView.bounds
      backgroundView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      rootView.addSubview(backgroundView)
    }

    previewView.backgroundColor = .black
    previewView.clipsToBounds = true
    previewView.accessibilityIdentifier = Identifier.preview
    if let previewLayer = source?.previewLayer {
      previewView.layer.addSublayer(previewLayer)
    }
    // Like Telegram, a double tap on the circle switches the camera too
    let flipRecognizer = UITapGestureRecognizer(target: self, action: #selector(handlePreviewDoubleTap))
    flipRecognizer.numberOfTapsRequired = 2
    previewView.addGestureRecognizer(flipRecognizer)
    spinner.color = .white
    spinner.hidesWhenStopped = true

    recordingDot.backgroundColor = .systemRed
    recordingDot.layer.cornerRadius = Self.dotSize / 2
    timerLabel.font = .monospacedDigitSystemFont(ofSize: Self.timerFontSize, weight: .semibold)
    timerLabel.textColor = .white
    showDuration(0)
    timerLabel.accessibilityLabel = Strings.recordingTime
    timerLabel.accessibilityIdentifier = Identifier.timer
    timerView.axis = .horizontal
    timerView.alignment = .center
    timerView.spacing = Self.dotSpacing
    timerView.addArrangedSubview(recordingDot)
    timerView.addArrangedSubview(timerLabel)

    configureMessageView()
    viewOnceButton.isHidden = !canSendOneTimeMedia

    let views: [UIView] = [
      ringView, previewView, spinner, timerView, cancelButton, sendButton, flipButton, flashButton, viewOnceButton,
      messageView,
    ]
    for view in views {
      view.translatesAutoresizingMaskIntoConstraints = false
      rootView.addSubview(view)
    }
    activateConstraints(in: rootView)
    view = rootView
    updateControls()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    observeApplication()
    guard let source else {
      showMessage(.noCamera)
      return
    }
    spinner.startAnimating()
    if ProcessInfo.processInfo.thermalState == .critical {
      showMessage(.tooWarm)
      return
    }
    // The synthetic source of the UI tests needs no access
    if source is RoundVideoCamera {
      requestAccess { [weak self] isGranted in
        if isGranted {
          self?.prepareSource()
        } else {
          self?.showMessage(.accessDenied)
        }
      }
    } else {
      prepareSource()
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !isVisible else {
      return
    }
    isVisible = true
    // The screen stays on while the hands are busy holding the phone up
    previousIdleTimerSetting = UIApplication.shared.isIdleTimerDisabled
    UIApplication.shared.isIdleTimerDisabled = true
    startSourceIfReady()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let bounds = previewView.bounds
    previewView.layer.cornerRadius = bounds.width / 2
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    source?.previewLayer.frame = bounds
    playerLayer?.frame = bounds
    CATransaction.commit()
  }

  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    logger.notice("Memory warning while recording a round video")
    if let source, let writer {
      source.queue.async {
        writer.clearCaches()
      }
    }
  }

  /// Ends the recorder without sending, for example because the page that opened it is gone
  func cancelRecording(reason: String) {
    discardRecording()
    close(.closed(reason: reason))
  }

  // MARK: - Starting

  private static func requestAccess(for mediaType: AVMediaType, completion: @escaping (Bool) -> Void) {
    switch AVCaptureDevice.authorizationStatus(for: mediaType) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: mediaType) { isGranted in
        DispatchQueue.main.async {
          completion(isGranted)
        }
      }
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }

  /// Asks for the camera, then the microphone; iOS asks the user only once for each
  private func requestAccess(completion: @escaping (Bool) -> Void) {
    Self.requestAccess(for: .video) { isCameraGranted in
      guard isCameraGranted else {
        completion(false)
        return
      }
      Self.requestAccess(for: .audio, completion: completion)
    }
  }

  private func prepareSource() {
    guard let source, case .preparing = phase else {
      return
    }
    source.prepare { [weak self] result in
      guard let self, case .preparing = self.phase else {
        return
      }
      switch result {
      case .success:
        self.makeWriter(for: source)
      case .failure(let error):
        logger.error("Could not set the camera up: \(String(describing: error), privacy: .public)")
        self.showMessage(.busy)
      }
    }
  }

  /// The writer gets every frame from the start, so the first frame starts the recording
  private func makeWriter(for source: RoundVideoSource) {
    let writer: RoundVideoWriter
    do {
      let fileURL = try MediaStore.shared.makeFileURL(pathExtension: RoundVideoFormat.fileExtension)
      writer = try RoundVideoWriter(outputURL: fileURL, hasAudio: source.hasAudio)
    } catch {
      logger.error("Could not create the video file: \(String(describing: error), privacy: .public)")
      showMessage(.failed)
      return
    }
    self.writer = writer
    source.sampleBufferHandler = { [weak self] sampleBuffer, isVideo in
      guard isVideo else {
        writer.appendAudio(sampleBuffer)
        return
      }
      let result = writer.appendVideo(sampleBuffer)
      switch result {
      case .started, .limitReached, .failed:
        DispatchQueue.main.async {
          self?.handleWriterResult(result)
        }
      case .appended, .dropped, .ignored:
        break
      }
    }
    source.eventHandler = { [weak self] event in
      self?.handle(event)
    }
    source.queue.async {
      writer.start()
    }
    isPrepared = true
    startSourceIfReady()
  }

  /// The camera's rotation needs the preview on screen, so the source starts once the recorder appeared
  private func startSourceIfReady() {
    guard let source, isPrepared, isVisible, !isStarting, case .preparing = phase else {
      return
    }
    isStarting = true
    source.start(interfaceOrientation: recordingOrientation) { [weak self] result in
      guard let self, case .failure(let error) = result else {
        return
      }
      logger.error("Could not start the camera: \(String(describing: error), privacy: .public)")
      if case .preparing = self.phase {
        self.showMessage(.busy)
      }
    }
  }

  private func handleWriterResult(_ result: RoundVideoWriter.VideoResult) {
    switch result {
    case .started:
      guard case .preparing = phase else {
        return
      }
      phase = .recording(startTime: CACurrentMediaTime())
      spinner.stopAnimating()
      startDisplayLink()
      playImpact(.medium)
      updateControls()
    case .limitReached:
      playNotification(.warning)
      stopRecording(reason: "limit")
    case .failed:
      showMessage(.failed)
    case .appended, .dropped, .ignored:
      break
    }
  }

  private func handle(_ event: RoundVideoSourceEvent) {
    switch event {
    case .interrupted:
      guard case .preparing = phase else {
        stopRecording(reason: "interrupted")
        return
      }
      // Leaving the app before the first frame cancels quietly; a busy camera in the open app needs a word
      if UIApplication.shared.applicationState == .active {
        showMessage(.busy)
      } else {
        cancelRecording(reason: "interrupted")
      }
    case .systemPressureShutdown:
      if case .preparing = phase {
        showMessage(.tooWarm)
      } else {
        stopRecording(reason: "systemPressure")
      }
    case .failed:
      if case .preparing = phase {
        showMessage(.failed)
      } else {
        stopRecording(reason: "captureFailed")
      }
    }
  }

  // MARK: - Actions

  private func send() {
    switch phase {
    case .recording(let startTime):
      guard CACurrentMediaTime() - startTime >= RoundVideoFormat.minDuration.seconds else {
        return
      }
      finishWriting { [weak self] recording in
        self?.close(.recorded(recording, isViewOnce: self?.isViewOnce ?? false))
      }
    case .stopped(let recording):
      close(.recorded(recording, isViewOnce: isViewOnce))
    case .preparing, .finishing, .message, .closed:
      break
    }
  }

  private func cancel() {
    if case .finishing = phase {
      return
    }
    discardRecording()
    close(.closed(reason: "cancelled"))
  }

  @objc private func handlePreviewDoubleTap() {
    switchCamera()
  }

  private func switchCamera() {
    guard let source, source.canSwitchCamera, !isSwitchingCamera, case .recording = phase else {
      return
    }
    // Like Telegram, at most one switch a second, since each one blanks the preview for a moment
    let now = CACurrentMediaTime()
    guard now - lastFlipTime >= Self.flipInterval else {
      return
    }
    lastFlipTime = now
    isSwitchingCamera = true
    playImpact(.light)
    UIView.transition(
      with: previewView,
      duration: Self.flipAnimationDuration,
      options: [.transitionFlipFromLeft, .allowAnimatedContent],
      animations: nil
    )
    source.switchCamera { [weak self] in
      guard let self else {
        return
      }
      self.isSwitchingCamera = false
      self.applyFlash()
    }
  }

  private func toggleFlash() {
    isFlashOn.toggle()
    playImpact(.light)
    applyFlash()
  }

  private func toggleViewOnce() {
    isViewOnce.toggle()
    if NativeSettings.isHapticsEnabled {
      UISelectionFeedbackGenerator().selectionChanged()
    }
    updateControls()
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else {
      return
    }
    UIApplication.shared.open(url)
    close(.closed(reason: Message.accessDenied.reason))
  }

  // MARK: - Stopping

  /// Keeps a recording of a second or more for Send or Cancel and closes the recorder without a shorter one
  private func stopRecording(reason: String) {
    guard case .recording(let startTime) = phase else {
      return
    }
    logger.info("Stopped recording: \(reason, privacy: .public)")
    let isLongEnough = CACurrentMediaTime() - startTime >= RoundVideoFormat.minDuration.seconds || reason == "limit"
    guard isLongEnough else {
      cancelRecording(reason: reason)
      return
    }
    // The file must be complete even if iOS suspends the app right after it went to the background
    beginBackgroundTask()
    finishWriting { [weak self] recording in
      self?.showStoppedRecording(recording)
      self?.endBackgroundTask()
    }
  }

  /// Closes the file; `completion` runs on the main queue with a complete recording. A failure shows its message.
  private func finishWriting(completion: @escaping (RoundVideoRecording) -> Void) {
    guard let source, let writer else {
      showMessage(.failed)
      return
    }
    phase = .finishing
    stopDisplayLink()
    updateControls()
    source.queue.async {
      writer.finish { result in
        DispatchQueue.main.async { [weak self] in
          guard let self, case .finishing = self.phase else {
            if case .success(let recording) = result {
              try? FileManager.default.removeItem(at: recording.fileURL)
            }
            return
          }
          switch result {
          case .success(let recording):
            completion(recording)
          case .failure(let error):
            logger.error("Could not finish the round video: \(String(describing: error), privacy: .public)")
            self.showMessage(.failed)
          }
        }
      }
    }
  }

  /// Stops the camera and loops the recording, muted, in the circle
  private func showStoppedRecording(_ recording: RoundVideoRecording) {
    phase = .stopped(recording)
    stopSource()
    restoreScreen()
    let player = AVQueuePlayer()
    player.isMuted = true
    playerLooper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: recording.fileURL))
    let playerLayer = AVPlayerLayer(player: player)
    playerLayer.videoGravity = .resizeAspectFill
    playerLayer.frame = previewView.bounds
    previewView.layer.addSublayer(playerLayer)
    player.play()
    self.player = player
    self.playerLayer = playerLayer
    showDuration(recording.duration.seconds)
    ringView.progress = CGFloat(recording.duration.seconds / RoundVideoFormat.maxDuration.seconds)
    updateControls()
  }

  private func discardRecording() {
    guard let source, let writer else {
      return
    }
    source.queue.async {
      writer.cancel()
    }
    if case .stopped(let recording) = phase {
      player?.pause()
      try? FileManager.default.removeItem(at: recording.fileURL)
    }
  }

  private func showMessage(_ message: Message) {
    if case .closed = phase {
      return
    }
    logger.info("The round video recorder shows the message \(message.reason, privacy: .public)")
    discardRecording()
    phase = .message
    messageReason = message.reason
    stopSource()
    stopDisplayLink()
    spinner.stopAnimating()
    restoreScreen()

    let title: String
    let text: String
    switch message {
    case .accessDenied:
      title = Strings.accessDeniedTitle
      text = Strings.accessDeniedMessage
    case .noCamera:
      title = Strings.noCameraTitle
      text = Strings.noCameraMessage
    case .busy:
      title = Strings.busyTitle
      text = Strings.busyMessage
    case .tooWarm:
      title = Strings.tooWarmTitle
      text = Strings.tooWarmMessage
    case .failed:
      title = Strings.failedTitle
      text = Strings.failedMessage
    }
    messageTitleLabel.text = title
    messageTextLabel.text = text
    settingsButton.isHidden = message != .accessDenied
    updateControls()
    UIAccessibility.post(notification: .screenChanged, argument: messageTitleLabel)
  }

  /// Dismisses the recorder and reports `outcome` once the recorder is gone
  private func close(_ outcome: RoundVideoRecorderOutcome) {
    if case .closed = phase {
      return
    }
    phase = .closed
    stopDisplayLink()
    stopSource()
    restoreScreen()
    player?.pause()
    if let previousIdleTimerSetting {
      UIApplication.shared.isIdleTimerDisabled = previousIdleTimerSetting
    }
    endBackgroundTask()
    let completion = completion
    if presentingViewController == nil {
      completion(outcome)
    } else {
      dismiss(animated: true) {
        completion(outcome)
      }
    }
  }

  private func stopSource() {
    guard let source else {
      return
    }
    source.setTorchEnabled(false)
    source.stop(completion: nil)
    // The handler holds the writer; it is read on the source's queue
    source.queue.async {
      source.sampleBufferHandler = nil
    }
  }

  // MARK: - App state

  private func observeApplication() {
    notificationObservers = [
      // The camera stops in the background, so the recording ends with what it has
      observeNotification(UIApplication.didEnterBackgroundNotification) { recorder in
        if case .preparing = recorder.phase {
          recorder.cancelRecording(reason: "background")
        } else {
          recorder.stopRecording(reason: "background")
        }
      },
      // Control Center and calls cover the app; the brightness of the screen flash must not stay for them
      observeNotification(UIApplication.willResignActiveNotification) { recorder in
        recorder.restoreBrightness()
      },
      observeNotification(UIApplication.didBecomeActiveNotification) { recorder in
        recorder.applyFlash()
      },
      observeNotification(ProcessInfo.thermalStateDidChangeNotification) { recorder in
        if ProcessInfo.processInfo.thermalState == .critical {
          recorder.stopRecording(reason: "thermalState")
        }
      },
    ]
  }

  /// Calls `handler` on the main queue for every notification named `name` while the recorder exists
  private func observeNotification(
    _ name: Notification.Name,
    handler: @escaping (RoundVideoRecorderViewController) -> Void
  ) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        if let self {
          handler(self)
        }
      }
    }
  }

  private func beginBackgroundTask() {
    guard backgroundTask == .invalid else {
      return
    }
    backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else {
      return
    }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  // MARK: - Flash

  private var isScreenFlashVisible: Bool {
    guard isFlashOn, source?.isFrontCamera == true, case .recording = phase else {
      return false
    }
    return true
  }

  /// The front camera gets light from the screen, at full brightness; the back camera from its torch
  private func applyFlash() {
    let isScreenFlash = isScreenFlashVisible
    let isTorch: Bool
    if case .recording = phase, isFlashOn, source?.isFrontCamera == false {
      isTorch = source?.hasTorch == true
    } else {
      isTorch = false
    }
    source?.setTorchEnabled(isTorch)
    UIView.animate(withDuration: Self.flashAnimationDuration) {
      self.flashView.alpha = isScreenFlash ? 1 : 0
      self.dimView.alpha = isScreenFlash ? 0 : 1
    }
    applyForeground(isScreenFlash: isScreenFlash)
    if isScreenFlash, UIApplication.shared.applicationState == .active, let screen = view.window?.windowScene?.screen {
      if initialBrightness == nil {
        initialBrightness = screen.brightness
      }
      screen.brightness = 1
    } else {
      restoreBrightness()
    }
    setNeedsStatusBarAppearanceUpdate()
    updateControls()
  }

  private func restoreBrightness() {
    guard let initialBrightness else {
      return
    }
    self.initialBrightness = nil
    view.window?.windowScene?.screen.brightness = initialBrightness
  }

  /// Turns the screen flash and the torch off for good
  private func restoreScreen() {
    restoreBrightness()
    source?.setTorchEnabled(false)
    flashView.alpha = 0
    dimView.alpha = 1
    applyForeground(isScreenFlash: false)
    setNeedsStatusBarAppearanceUpdate()
  }

  /// Light controls on the dimmed chat, dark ones on the screen flash
  private func applyForeground(isScreenFlash: Bool) {
    let color = isScreenFlash ? Self.flashForegroundColor : UIColor.white
    viewIfLoaded?.overrideUserInterfaceStyle = isScreenFlash ? .light : .dark
    timerLabel.textColor = color
    ringView.color = color
    cancelButton.configuration?.baseForegroundColor = color
    // Glass picks its own content color for what is behind it
    if #unavailable(iOS 26.0) {
      let backgroundColor = (isScreenFlash ? UIColor.black : UIColor.white)
        .withAlphaComponent(Self.buttonBackgroundAlpha)
      for button in [flipButton, flashButton, viewOnceButton] {
        button.configuration?.baseForegroundColor = color
        button.configuration?.baseBackgroundColor = backgroundColor
      }
    }
  }

  // MARK: - Progress

  private static func formatDuration(_ seconds: Double) -> String {
    let wholeSeconds = max(0, Int(seconds))
    return String(format: "%d:%02d", wholeSeconds / secondsPerMinute, wholeSeconds % secondsPerMinute)
  }

  /// Shows the elapsed whole seconds as `m:ss`, which VoiceOver hears in words
  private func showDuration(_ seconds: Double) {
    timerLabel.text = Self.formatDuration(seconds)
    timerLabel.accessibilityValue = Self.spokenDurationFormatter.string(from: Double(max(0, Int(seconds))))
  }

  private func startDisplayLink() {
    guard displayLink == nil else {
      return
    }
    let displayLink = CADisplayLink(target: DisplayLinkTarget(owner: self), selector: #selector(DisplayLinkTarget.tick))
    displayLink.preferredFrameRateRange = CAFrameRateRange(
      minimum: Self.displayLinkFrameRate / 2,
      maximum: Self.displayLinkFrameRate,
      preferred: Self.displayLinkFrameRate
    )
    displayLink.add(to: .main, forMode: .common)
    self.displayLink = displayLink
  }

  private func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
  }

  fileprivate func updateProgress() {
    guard case .recording(let startTime) = phase else {
      return
    }
    let elapsed = CACurrentMediaTime() - startTime
    ringView.progress = CGFloat(min(1, elapsed / RoundVideoFormat.maxDuration.seconds))
    let pulse = (1 + cos(elapsed / Self.pulsePeriod * 2 * .pi)) / 2
    recordingDot.alpha = Self.pulseMinimumAlpha + (1 - Self.pulseMinimumAlpha) * CGFloat(pulse)
    if timerLabel.text != Self.formatDuration(elapsed) {
      showDuration(elapsed)
      // Send works from the minimum duration on
      updateControls()
    }
  }

  private func playImpact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
    if NativeSettings.isHapticsEnabled {
      UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
  }

  private func playNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
    if NativeSettings.isHapticsEnabled {
      UINotificationFeedbackGenerator().notificationOccurred(type)
    }
  }

  // MARK: - Layout

  private func updateControls() {
    var isRecording = false
    var isCapturing = false
    var canSend = false
    var isMessage = false
    switch phase {
    case .preparing, .finishing:
      isCapturing = true
    case .recording(let startTime):
      isRecording = true
      isCapturing = true
      canSend = CACurrentMediaTime() - startTime >= RoundVideoFormat.minDuration.seconds
    case .stopped:
      canSend = true
    case .message:
      isMessage = true
    case .closed:
      break
    }

    for recorderView in [previewView, ringView, timerView, cancelButton, sendButton] as [UIView] {
      recorderView.isHidden = isMessage
    }
    messageView.isHidden = !isMessage
    // Switching the camera and the flash only make sense while the camera runs
    flipButton.isHidden = !isCapturing || source?.canSwitchCamera != true
    flipButton.isEnabled = isRecording && !isSwitchingCamera
    flashButton.isHidden = !isCapturing
    flashButton.isEnabled = isRecording
    viewOnceButton.isHidden = isMessage || !canSendOneTimeMedia
    sendButton.isEnabled = canSend
    sendButton.alpha = canSend ? 1 : Self.disabledAlpha
    recordingDot.backgroundColor = isRecording ? .systemRed : .systemGray
    if !isRecording {
      recordingDot.alpha = 1
    }

    flashButton.configuration?.image = makeSymbol(isFlashOn ? "bolt.fill" : "bolt.slash.fill")
    flashButton.accessibilityValue = isFlashOn ? Strings.on : Strings.off
    viewOnceButton.configuration?.image = makeSymbol(isViewOnce ? "1.circle.fill" : "1.circle")
    viewOnceButton.accessibilityValue = isViewOnce ? Strings.on : Strings.off
    viewOnceButton.accessibilityTraits = isViewOnce ? [.button, .selected] : .button
  }

  private func activateConstraints(in rootView: UIView) {
    let safeArea = rootView.safeAreaLayoutGuide
    // The circle is centred in the area above the buttons
    let contentGuide = UILayoutGuide()
    rootView.addLayoutGuide(contentGuide)
    let preferredPreviewWidth = previewView.widthAnchor.constraint(
      equalTo: rootView.widthAnchor,
      multiplier: Self.previewWidthRatio
    )
    preferredPreviewWidth.priority = .defaultHigh

    NSLayoutConstraint.activate([
      sendButton.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -Self.sideInset),
      sendButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -Self.bottomInset),
      sendButton.widthAnchor.constraint(equalToConstant: Self.sendButtonSize),
      sendButton.heightAnchor.constraint(equalToConstant: Self.sendButtonSize),
      cancelButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
      cancelButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
      timerView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: Self.timerInset),
      timerView.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor),
      recordingDot.widthAnchor.constraint(equalToConstant: Self.dotSize),
      recordingDot.heightAnchor.constraint(equalToConstant: Self.dotSize),

      flipButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: Self.sideInset),
      flipButton.bottomAnchor.constraint(equalTo: sendButton.topAnchor, constant: -Self.rowSpacing),
      flipButton.widthAnchor.constraint(equalToConstant: Self.smallButtonSize),
      flipButton.heightAnchor.constraint(equalToConstant: Self.smallButtonSize),
      flashButton.leadingAnchor.constraint(equalTo: flipButton.trailingAnchor, constant: Self.buttonSpacing),
      flashButton.centerYAnchor.constraint(equalTo: flipButton.centerYAnchor),
      flashButton.widthAnchor.constraint(equalToConstant: Self.smallButtonSize),
      flashButton.heightAnchor.constraint(equalToConstant: Self.smallButtonSize),
      viewOnceButton.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
      viewOnceButton.centerYAnchor.constraint(equalTo: flipButton.centerYAnchor),
      viewOnceButton.widthAnchor.constraint(equalToConstant: Self.smallButtonSize),
      viewOnceButton.heightAnchor.constraint(equalToConstant: Self.smallButtonSize),

      contentGuide.topAnchor.constraint(equalTo: safeArea.topAnchor),
      contentGuide.bottomAnchor.constraint(equalTo: flipButton.topAnchor),
      contentGuide.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
      contentGuide.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
      previewView.centerXAnchor.constraint(equalTo: contentGuide.centerXAnchor),
      previewView.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
      previewView.heightAnchor.constraint(equalTo: previewView.widthAnchor),
      preferredPreviewWidth,
      previewView.widthAnchor.constraint(lessThanOrEqualTo: contentGuide.heightAnchor, constant: -Self.previewMargin),
      previewView.widthAnchor.constraint(lessThanOrEqualTo: contentGuide.widthAnchor, constant: -Self.previewMargin),
      ringView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
      ringView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
      ringView.widthAnchor.constraint(equalTo: previewView.widthAnchor, constant: Self.ringOutset * 2),
      ringView.heightAnchor.constraint(equalTo: ringView.widthAnchor),
      spinner.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
      spinner.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),

      messageView.centerYAnchor.constraint(equalTo: contentGuide.centerYAnchor),
      messageView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: Self.messageInset),
      messageView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -Self.messageInset),
    ])
  }

  private func configureMessageView() {
    messageView.axis = .vertical
    messageView.alignment = .center
    messageView.spacing = Self.messageSpacing
    messageView.accessibilityIdentifier = Identifier.message
    messageView.isHidden = true

    messageIconView.image = UIImage(
      systemName: "video.slash.fill",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: Self.messageIconPointSize, weight: .regular)
    )
    messageIconView.tintColor = .white
    messageIconView.isAccessibilityElement = false
    messageTitleLabel.font = .preferredFont(forTextStyle: .title3)
    messageTitleLabel.adjustsFontForContentSizeCategory = true
    messageTitleLabel.textColor = .white
    messageTitleLabel.textAlignment = .center
    messageTitleLabel.numberOfLines = 0
    messageTitleLabel.accessibilityTraits = .header
    messageTextLabel.font = .preferredFont(forTextStyle: .body)
    messageTextLabel.adjustsFontForContentSizeCategory = true
    messageTextLabel.textColor = UIColor.white.withAlphaComponent(Self.messageTextAlpha)
    messageTextLabel.textAlignment = .center
    messageTextLabel.numberOfLines = 0

    for messagePart in [messageIconView, messageTitleLabel, messageTextLabel, settingsButton, closeButton] {
      messageView.addArrangedSubview(messagePart)
    }
    messageView.setCustomSpacing(Self.messageSpacing * 2, after: messageTextLabel)
  }

  private func makeSymbol(
    _ name: String,
    pointSize: CGFloat = RoundVideoRecorderViewController.iconPointSize
  ) -> UIImage? {
    UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
  }

  private func makeRoundButton(
    symbolName: String,
    identifier: String,
    label: String,
    action: @escaping () -> Void
  ) -> UIButton {
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *) {
      configuration = .glass()
    } else {
      configuration = .filled()
      configuration.baseBackgroundColor = UIColor.white.withAlphaComponent(Self.buttonBackgroundAlpha)
    }
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = .white
    configuration.image = makeSymbol(symbolName)
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in
      action()
    })
    button.accessibilityIdentifier = identifier
    button.accessibilityLabel = label
    return button
  }

  private func makeSendButton() -> UIButton {
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *) {
      configuration = .prominentGlass()
    } else {
      configuration = .filled()
    }
    configuration.cornerStyle = .capsule
    configuration.baseBackgroundColor = Self.accentColor
    configuration.baseForegroundColor = .white
    configuration.image = makeSymbol("arrow.up", pointSize: Self.sendIconPointSize)
    let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
      self?.send()
    })
    button.tintColor = Self.accentColor
    button.accessibilityIdentifier = Identifier.send
    button.accessibilityLabel = Strings.send
    return button
  }

  private func makeTextButton(title: String, identifier: String, action: @escaping () -> Void) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.baseForegroundColor = .white
    configuration.buttonSize = .large
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in
      action()
    })
    button.accessibilityIdentifier = identifier
    return button
  }
}

/// Forwards display link ticks without the display link retaining the recorder
private final class DisplayLinkTarget: NSObject {
  private weak var owner: RoundVideoRecorderViewController?

  init(owner: RoundVideoRecorderViewController) {
    self.owner = owner
    super.init()
  }

  @objc func tick() {
    owner?.updateProgress()
  }
}

/// The ring around the circle: a faint track and the elapsed part of the duration limit, from the top clockwise
private final class RecorderRingView: UIView {
  private static let trackAlpha: CGFloat = 0.2

  private let lineWidth: CGFloat
  private let trackLayer = CAShapeLayer()
  private let progressLayer = CAShapeLayer()

  init(lineWidth: CGFloat) {
    self.lineWidth = lineWidth
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    for layer in [trackLayer, progressLayer] {
      layer.fillColor = UIColor.clear.cgColor
      layer.lineWidth = lineWidth
      layer.lineCap = .round
      self.layer.addSublayer(layer)
    }
    applyColor()
    progressLayer.strokeEnd = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  var color = UIColor.white {
    didSet {
      applyColor()
    }
  }

  /// From 0 to 1, without animation, since it follows the display
  var progress: CGFloat = 0 {
    didSet {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      progressLayer.strokeEnd = progress
      CATransaction.commit()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let radius = max(0, bounds.width / 2 - lineWidth / 2)
    let path = UIBezierPath(
      arcCenter: center,
      radius: radius,
      startAngle: -.pi / 2,
      endAngle: 1.5 * .pi,
      clockwise: true
    ).cgPath
    for layer in [trackLayer, progressLayer] {
      layer.frame = bounds
      layer.path = path
    }
  }

  private func applyColor() {
    trackLayer.strokeColor = color.withAlphaComponent(Self.trackAlpha).cgColor
    progressLayer.strokeColor = color.cgColor
  }
}
