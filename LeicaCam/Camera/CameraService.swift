import AVFoundation
import CoreImage
import Photos
import UIKit

/// A captured photo ready for review. The `id` is assigned once at capture so
/// it stays stable across re-renders (see `CameraService.captured`).
struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
    let original: UIImage?
}

/// Central hub for the camera. Owns the `AVCaptureSession`, streams processed
/// preview frames to a `MetalRenderer`, and drives photo capture through the
/// `ImagePipeline`. Published properties drive the SwiftUI viewfinder.
final class CameraService: NSObject, ObservableObject {

    enum CameraState: Equatable { case unconfigured, configured, denied, failed(String) }

    // MARK: - Published UI state
    @Published var state: CameraState = .unconfigured
    @Published var selectedStyle: AppStyle = AppStyleLibrary.default
    @Published var exposureBias: Float = 0.0          // EV, -3...3
    @Published var iso: Float = 0
    @Published var focusIndicator: CGPoint? = nil      // normalized view point
    /// Non-nil => present the review screen. Its `id` is created once per
    /// capture so SwiftUI's `fullScreenCover(item:)` keeps a stable identity
    /// across the frequent `@Published` updates (ISO, flash) the camera emits.
    @Published var captured: CapturedPhoto? = nil
    @Published var lastThumbnail: UIImage? = nil
    @Published var flashOpacity: Double = 0            // shutter flash overlay
    @Published var showGrid: Bool = false

    /// Persist the unprocessed original alongside the processed photo.
    var saveOriginal = false

    // MARK: - AV plumbing
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session")
    private let videoQueue = DispatchQueue(label: "camera.video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?

    private let pipeline = ImagePipeline()
    private let captureContext = CIContext(options: [.cacheIntermediates: false])
    private var frameCounter = 0
    private var inFlight: [Int64: PhotoCaptureProcessor] = [:]

    weak var renderer: MetalRenderer?

    // MARK: - Lifecycle ---------------------------------------------------

    func start() {
        checkPermissionsAndConfigure()
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func checkPermissionsAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                self?.sessionQueue.resume()
                if granted { self?.configure() }
                else { DispatchQueue.main.async { self?.state = .denied } }
            }
        default:
            DispatchQueue.main.async { self.state = .denied }
        }
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video, position: .back) else {
                self.fail("No wide-angle camera available")
                return
            }
            self.device = device

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else {
                    self.fail("Cannot add camera input"); return
                }
                self.session.addInput(input)
            } catch {
                self.fail("Camera input error: \(error.localizedDescription)"); return
            }

            // Live preview frames.
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            guard self.session.canAddOutput(self.videoOutput) else {
                self.fail("Cannot add video output"); return
            }
            self.session.addOutput(self.videoOutput)

            // Final capture.
            guard self.session.canAddOutput(self.photoOutput) else {
                self.fail("Cannot add photo output"); return
            }
            self.session.addOutput(self.photoOutput)
            self.photoOutput.maxPhotoQualityPrioritization = .quality

            self.applyRotation(to: self.videoOutput.connection(with: .video))

            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.state = .configured }
        }
    }

    private func applyRotation(to connection: AVCaptureConnection?) {
        guard let connection else { return }
        // Portrait = 90°.
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func fail(_ message: String) {
        self.session.commitConfiguration()
        DispatchQueue.main.async { self.state = .failed(message) }
    }

    // MARK: - Controls ----------------------------------------------------

    /// Exposure compensation, clamped to the device's supported range.
    func setExposureBias(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            let clamped = min(device.maxExposureTargetBias,
                              max(device.minExposureTargetBias, ev))
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.exposureBias = clamped }
            } catch { /* ignore transient lock failures */ }
        }
    }

    /// Tap-to-focus. `point` is normalized (0...1) in the preview view's space
    /// (origin top-left). Shows a focus indicator that auto-expires after 2s.
    func focus(atViewPoint point: CGPoint) {
        DispatchQueue.main.async {
            self.focusIndicator = point
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if self.focusIndicator == point { self.focusIndicator = nil }
            }
        }
        // Map portrait view point -> device point of interest.
        let devicePoint = CGPoint(x: point.y, y: 1 - point.x)
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch { /* ignore */ }
        }
    }

    // MARK: - Capture -----------------------------------------------------

    func capturePhoto() {
        let style = selectedStyle
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.applyRotation(to: self.photoOutput.connection(with: .video))
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()  // JPEG fallback
            }
            settings.photoQualityPrioritization = .quality

            let processor = PhotoCaptureProcessor(
                style: style,
                pipeline: self.pipeline,
                context: self.captureContext,
                saveOriginal: self.saveOriginal,
                onComplete: { [weak self] result in
                    guard let self else { return }
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let image, let original):
                            self.captured = CapturedPhoto(image: image, original: original)
                            self.lastThumbnail = image
                        case .failure(let message):
                            self.state = .failed(message)
                        }
                    }
                },
                saveOriginalData: { [weak self] data in self?.saveToLibrary(data: data) }
            )
            // Retain the processor until it reports completion.
            self.inFlight[settings.uniqueID] = processor
            processor.onFinished = { [weak self] id in self?.inFlight[id] = nil }
            self.photoOutput.capturePhoto(with: settings, delegate: processor)
        }
        // Shutter flash animation cue; the view animates the fade via the
        // published value change.
        DispatchQueue.main.async {
            self.flashOpacity = 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.flashOpacity = 0 }
        }
    }
}

// MARK: - Live preview frames

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let processed = pipeline.processPreview(source, style: currentStyleSnapshot)
        renderer?.display(image: processed)

        // Throttled ISO readout.
        frameCounter += 1
        if frameCounter % 15 == 0, let device {
            let currentISO = device.iso
            DispatchQueue.main.async { self.iso = currentISO }
        }
    }

    /// Read the selected style without hopping to the main queue per frame.
    private var currentStyleSnapshot: AppStyle {
        // `selectedStyle` is a value type; reading is safe enough for preview.
        selectedStyle
    }
}

// MARK: - Photos saving

extension CameraService {
    /// Save a processed `UIImage` (called from the review screen on "Save").
    func save(image: UIImage, completion: @escaping (Bool) -> Void) {
        requestAddAuthorization { granted in
            guard granted else { completion(false); return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success) }
            }
        }
    }

    private func saveToLibrary(data: Data) {
        requestAddAuthorization { granted in
            guard granted else { return }
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            }
        }
    }

    private func requestAddAuthorization(_ completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        default:
            completion(false)
        }
    }
}
