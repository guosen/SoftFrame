import AVFoundation
import Combine
import CoreImage
import UIKit

enum CaptureMode {
    case photo
    case video
}

struct PendingShot {
    let recipe: FilterRecipe
    let screenAspect: CGFloat
    let bufferAspect: CGFloat
}

final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var previewImage: UIImage?
    @Published var isRecording = false
    @Published var recordingSeconds = 0
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var isFront = false
    @Published var mode: CaptureMode = .photo
    @Published var cameraDenied = false
    @Published var hasFlash = false
    @Published var inFlightCaptures = 0
    @Published var needsSilentConfirm = false

    var onPhotoReady: ((URL) -> Void)?
    var onVideoReady: ((URL) -> Void)?
    var onMessage: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "softframe.camera.session")
    private let renderQueue = DispatchQueue(label: "softframe.camera.render")
    private let visionQueue = DispatchQueue(label: "softframe.camera.vision")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var configured = false
    private let engine = FilterEngine.shared

    private let stateLock = NSLock()
    private var recipe = FilterRecipe.initial
    private var faceRects: [CGRect] = []
    private var previewAspect: CGFloat = 9.0 / 19.5
    private var bufferAspect: CGFloat = 3.0 / 4.0
    private var grainPhase: CGFloat = 0
    private var lastFaceTime: CFAbsoluteTime = 0
    private var detectingFaces = false
    private var recorder: FilteredVideoRecorder?
    private var pendingShots: [Int64: PendingShot] = [:]

    func setRecipe(_ recipe: FilterRecipe) {
        stateLock.lock()
        self.recipe = recipe
        stateLock.unlock()
    }

    func setPreviewAspect(_ aspect: CGFloat) {
        guard aspect > 0.2, aspect < 2 else { return }
        stateLock.lock()
        previewAspect = aspect
        stateLock.unlock()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureAndStart() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { self.cameraDenied = !granted }
                if granted {
                    self.sessionQueue.async { self.configureAndStart() }
                }
            }
        default:
            DispatchQueue.main.async { self.cameraDenied = true }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func flipCamera() {
        sessionQueue.async {
            self.position = self.position == .back ? .front : .back
            self.session.beginConfiguration()
            _ = self.installVideoInput()
            self.applyConnectionSettings()
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.isFront = self.position == .front
                self.hasFlash = self.videoInput?.device.hasFlash ?? false
            }
        }
    }

    func cycleFlash() {
        switch flashMode {
        case .off: flashMode = .on
        case .on: flashMode = .auto
        default: flashMode = .off
        }
    }

    func setMode(_ mode: CaptureMode) {
        guard !isRecording else { return }
        self.mode = mode
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = mode == .video ? .hd1920x1080 : .photo
            if mode == .photo {
                self.removeAudioInput()
            }
            self.applyMaxPhotoDimensions()
            self.applyConnectionSettings()
            self.session.commitConfiguration()
        }
    }

    func takePhoto() {
        guard inFlightCaptures < AppConfig.maxInFlightCaptures else { return }
        let recipe = currentRecipe()
        let aspects = currentAspects()
        inFlightCaptures += 1
        sessionQueue.async {
            guard self.configured, self.session.isRunning else {
                DispatchQueue.main.async {
                    self.inFlightCaptures = max(0, self.inFlightCaptures - 1)
                    self.onMessage?("相机还没准备好。")
                }
                return
            }
            let settings = AVCapturePhotoSettings()
            if #available(iOS 18.0, *), self.photoOutput.isShutterSoundSuppressionSupported {
                settings.isShutterSoundSuppressionEnabled = true
            }
            let maxDimensions = self.photoOutput.maxPhotoDimensions
            if maxDimensions.width > 0, maxDimensions.height > 0 {
                settings.maxPhotoDimensions = maxDimensions
            }
            settings.photoQualityPrioritization = .quality
            let flash = self.flashMode
            if self.photoOutput.supportedFlashModes.contains(flash) {
                settings.flashMode = flash
            }
            self.stateLock.lock()
            self.pendingShots[settings.uniqueID] = PendingShot(
                recipe: recipe,
                screenAspect: aspects.screen,
                bufferAspect: aspects.buffer
            )
            self.stateLock.unlock()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func toggleRecording() {
        if isRecording {
            renderQueue.async { self.finishRecording(enforceMinimum: true) }
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            beginRecording(audio: true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.beginRecording(audio: true)
                    } else {
                        self.onMessage?("麦克风没有打开，这段视频将没有声音。")
                        self.beginRecording(audio: false)
                    }
                }
            }
        default:
            needsSilentConfirm = true
        }
    }

    func confirmSilentRecording() {
        needsSilentConfirm = false
        beginRecording(audio: false)
    }

    private func beginRecording(audio: Bool) {
        sessionQueue.async {
            if audio {
                self.addAudioInput()
                self.activateAudioSession()
            }
            self.session.beginConfiguration()
            if self.session.sessionPreset != .hd1920x1080 {
                self.session.sessionPreset = .hd1920x1080
            }
            self.applyConnectionSettings()
            self.session.commitConfiguration()
            let hasAudio = self.audioInput != nil
            self.renderQueue.async {
                guard self.recorder == nil else { return }
                guard let recorder = FilteredVideoRecorder(recordAudio: hasAudio, context: self.engine.context) else {
                    DispatchQueue.main.async { self.onMessage?("视频暂时录不了，请再试一次。") }
                    return
                }
                self.recorder = recorder
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.recordingSeconds = 0
                }
                self.setTorch(on: self.flashMode == .on)
            }
        }
    }

    private func configureAndStart() {
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard installVideoInput() else {
                session.commitConfiguration()
                DispatchQueue.main.async { self.onMessage?("这台手机的相机打不开。") }
                return
            }
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            applyMaxPhotoDimensions()
            applyConnectionSettings()
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning {
            session.startRunning()
        }
        session.beginConfiguration()
        applyMaxPhotoDimensions()
        applyConnectionSettings()
        session.commitConfiguration()
        DispatchQueue.main.async {
            self.cameraDenied = false
            self.isFront = self.position == .front
            self.hasFlash = self.videoInput?.device.hasFlash ?? false
        }
    }

    @discardableResult
    private func installVideoInput() -> Bool {
        if let videoInput {
            session.removeInput(videoInput)
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        videoInput = input
        return true
    }

    private func applyMaxPhotoDimensions() {
        guard let device = videoInput?.device else { return }
        let dimensions = device.activeFormat.supportedMaxPhotoDimensions
        if let best = dimensions.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photoOutput.maxPhotoDimensions = best
        }
    }

    private func applyConnectionSettings() {
        let front = position == .front
        for output in [videoOutput as AVCaptureOutput, photoOutput] {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    private func addAudioInput() {
        session.beginConfiguration()
        if audioInput == nil,
           let device = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }
        if !session.outputs.contains(where: { $0 === audioOutput }), session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }
        session.commitConfiguration()
    }

    private func removeAudioInput() {
        if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }
        if session.outputs.contains(where: { $0 === audioOutput }) {
            session.removeOutput(audioOutput)
        }
    }

    private func activateAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        try? audio.setActive(true)
    }

    private func setTorch(on: Bool) {
        sessionQueue.async {
            guard let device = self.videoInput?.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if on, device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: 0.35)
                } else if device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                return
            }
        }
    }

    private func currentRecipe() -> FilterRecipe {
        stateLock.lock()
        defer { stateLock.unlock() }
        return recipe
    }

    private func currentAspects() -> (screen: CGFloat, buffer: CGFloat) {
        stateLock.lock()
        defer { stateLock.unlock() }
        return (previewAspect, bufferAspect)
    }

    private func render(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        if image.extent.width > image.extent.height * 1.05 {
            image = image.oriented(.right)
        }
        if image.extent.height > 1 {
            let aspect = image.extent.width / image.extent.height
            stateLock.lock()
            bufferAspect = aspect
            stateLock.unlock()
        }
        let recipe = currentRecipe()
        let faces = currentFaces()
        scheduleFaceDetectionIfNeeded(on: image, skin: recipe.skin)
        grainPhase += 1
        let filtered = engine.apply(to: image, recipe: recipe, grainPhase: grainPhase, faces: .known(faces))
        if let cgImage = engine.previewCGImage(from: filtered, maxWidth: 720) {
            let preview = UIImage(cgImage: cgImage)
            DispatchQueue.main.async { self.previewImage = preview }
        }
        guard let recorder else { return }
        recorder.append(image: filtered, at: time, engine: engine)
        let elapsed = recorder.seconds(since: time)
        let whole = Int(elapsed)
        DispatchQueue.main.async {
            if self.recordingSeconds != whole {
                self.recordingSeconds = whole
            }
        }
        if elapsed >= AppConfig.maxVideoSeconds {
            finishRecording(enforceMinimum: false)
        }
    }

    private func currentFaces() -> [CGRect] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return faceRects
    }

    private func scheduleFaceDetectionIfNeeded(on image: CIImage, skin: Double) {
        guard skin > 0.5 else {
            stateLock.lock()
            faceRects = []
            stateLock.unlock()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        stateLock.lock()
        let busy = detectingFaces
        let due = now - lastFaceTime > 0.4
        if !busy, due {
            detectingFaces = true
        }
        stateLock.unlock()
        guard !busy, due else { return }
        let small = engine.previewCGImage(from: image, maxWidth: 360).map { CIImage(cgImage: $0) } ?? image
        visionQueue.async {
            let rects = self.engine.normalizedFaces(in: small)
            self.stateLock.lock()
            self.faceRects = rects
            self.stateLock.unlock()
            self.stateLock.lock()
            self.lastFaceTime = CFAbsoluteTimeGetCurrent()
            self.detectingFaces = false
            self.stateLock.unlock()
        }
    }

    private func finishRecording(enforceMinimum: Bool) {
        guard let recorder else { return }
        self.recorder = nil
        setTorch(on: false)
        DispatchQueue.main.async {
            self.isRecording = false
            self.recordingSeconds = 0
        }
        if enforceMinimum && recorder.lastElapsed < AppConfig.minVideoSeconds {
            recorder.cancel()
            DispatchQueue.main.async { self.onMessage?("至少录 1 秒。") }
            return
        }
        Task {
            guard let url = await recorder.finish() else {
                await MainActor.run { self.onMessage?("这段视频保存失败，请再试一次。") }
                return
            }
            await MainActor.run { self.onVideoReady?(url) }
        }
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput {
            renderQueue.async { self.recorder?.appendAudio(sampleBuffer) }
            return
        }
        renderQueue.async {
            self.render(sampleBuffer: sampleBuffer)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        stateLock.lock()
        let pending = pendingShots.removeValue(forKey: photo.resolvedSettings.uniqueID)
        stateLock.unlock()
        guard error == nil, let data = photo.fileDataRepresentation(), let pending else {
            DispatchQueue.main.async {
                self.inFlightCaptures = max(0, self.inFlightCaptures - 1)
                if error != nil {
                    self.onMessage?("这张没有拍下来，请再试一次。")
                }
            }
            return
        }
        let engine = self.engine
        Task.detached {
            do {
                let decoded = try ImageDecoding.ciImage(from: data)
                let matched = pending.bufferAspect > 0.2 ? engine.centerCrop(decoded, to: pending.bufferAspect) : decoded
                let cropped = engine.centerCrop(matched, to: pending.screenAspect)
                let filtered = engine.apply(
                    to: cropped,
                    recipe: pending.recipe,
                    grainPhase: CGFloat.random(in: 0...800),
                    faces: .detect
                )
                let url = try engine.writeTemporary(image: filtered)
                await MainActor.run {
                    self.inFlightCaptures = max(0, self.inFlightCaptures - 1)
                    self.onPhotoReady?(url)
                }
            } catch {
                await MainActor.run {
                    self.inFlightCaptures = max(0, self.inFlightCaptures - 1)
                    self.onMessage?("这张没有处理完，请再试一次。")
                }
            }
        }
    }
}
