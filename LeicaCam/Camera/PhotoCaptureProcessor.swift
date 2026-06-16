import AVFoundation
import CoreImage
import UIKit

/// One-shot `AVCapturePhotoCaptureDelegate`. Receives the captured photo,
/// pushes it through the full `ImagePipeline`, and reports back a processed
/// `UIImage`. A fresh instance is created per capture and retained by
/// `CameraService` until `onFinished` fires.
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {

    enum Result {
        /// Processed image plus the unprocessed original (for before/after).
        case success(processed: UIImage, original: UIImage?)
        case failure(String)
    }

    private let style: LeicaStyle
    private let pipeline: ImagePipeline
    private let context: CIContext
    private let saveOriginal: Bool
    private let onComplete: (Result) -> Void
    private let saveOriginalData: (Data) -> Void

    /// Called with the capture's `uniqueID` once the delegate is finished, so
    /// the owner can release this processor.
    var onFinished: ((Int64) -> Void)?

    init(style: LeicaStyle,
         pipeline: ImagePipeline,
         context: CIContext,
         saveOriginal: Bool,
         onComplete: @escaping (Result) -> Void,
         saveOriginalData: @escaping (Data) -> Void) {
        self.style = style
        self.pipeline = pipeline
        self.context = context
        self.saveOriginal = saveOriginal
        self.onComplete = onComplete
        self.saveOriginalData = saveOriginalData
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            onComplete(.failure(error.localizedDescription))
            return
        }
        // HEIF (or JPEG fallback) bytes, with embedded orientation applied.
        guard let data = photo.fileDataRepresentation(),
              let source = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
            onComplete(.failure("Could not read captured photo data."))
            return
        }

        if saveOriginal { saveOriginalData(data) }

        let processed = pipeline.processCapture(source, style: style)
        guard let cg = context.createCGImage(processed, from: processed.extent) else {
            onComplete(.failure("Failed to render processed photo."))
            return
        }
        // Unprocessed original for the hold-to-compare feature.
        var original: UIImage?
        if let originalCG = context.createCGImage(source, from: source.extent) {
            original = UIImage(cgImage: originalCG)
        }
        onComplete(.success(processed: UIImage(cgImage: cg), original: original))
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                     error: Error?) {
        onFinished?(resolvedSettings.uniqueID)
    }
}
