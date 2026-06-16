import CoreImage
import MetalKit
import UIKit

/// GPU-accelerated `MTKView` that renders processed `CIImage` frames for the
/// live viewfinder. The camera pushes frames in via `display(_:)`; rendering
/// happens on the GPU through a shared `CIContext`.
final class MetalRenderer: MTKView, MTKViewDelegate {

    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private var currentImage: CIImage?
    private let lock = NSLock()

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        let dev = device ?? MTLCreateSystemDefaultDevice()!
        self.commandQueue = dev.makeCommandQueue()!
        self.ciContext = CIContext(mtlDevice: dev, options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .cacheIntermediates: false
        ])
        super.init(frame: frameRect, device: dev)
        configure()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func configure() {
        framebufferOnly = false                 // CIContext needs to write
        colorPixelFormat = .bgra8Unorm
        isPaused = true                          // draw on demand
        enableSetNeedsDisplay = true
        autoResizeDrawable = true
        backgroundColor = .black
        delegate = self
        contentMode = .scaleAspectFill
    }

    /// Push a new frame to display. Safe to call from the camera's video queue.
    func display(image: CIImage) {
        lock.lock(); currentImage = image; lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock(); let image = currentImage; lock.unlock()
        guard let image,
              let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let drawableSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)

        // Aspect-fill the source image into the drawable.
        let imageSize = image.extent.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = max(drawableSize.width / imageSize.width,
                        drawableSize.height / imageSize.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        // Centre the scaled image.
        let tx = (drawableSize.width - scaled.extent.width) / 2 - scaled.extent.origin.x
        let ty = (drawableSize.height - scaled.extent.height) / 2 - scaled.extent.origin.y
        let centered = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty))

        let destRect = CGRect(origin: .zero, size: drawableSize)
        ciContext.render(centered,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: destRect,
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
