import SwiftUI
import MetalKit

/// Bridges the Metal-backed `MetalRenderer` into SwiftUI and wires up
/// tap-to-focus plus vertical-swipe exposure compensation.
struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraService

    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }

    func makeUIView(context: Context) -> MetalRenderer {
        let view = MetalRenderer(frame: .zero, device: MTLCreateSystemDefaultDevice())
        camera.renderer = view
        context.coordinator.attachGestures(to: view)
        return view
    }

    func updateUIView(_ uiView: MetalRenderer, context: Context) {}

    final class Coordinator: NSObject {
        let camera: CameraService
        private var accumulatedEV: Float = 0

        init(camera: CameraService) { self.camera = camera }

        func attachGestures(to view: UIView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            view.addGestureRecognizer(tap)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            view.addGestureRecognizer(pan)
        }

        @objc private func handleTap(_ gr: UITapGestureRecognizer) {
            guard let view = gr.view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let p = gr.location(in: view)
            let normalized = CGPoint(x: p.x / view.bounds.width, y: p.y / view.bounds.height)
            camera.focus(atViewPoint: normalized)
        }

        @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let view = gr.view else { return }
            switch gr.state {
            case .began:
                accumulatedEV = camera.exposureBias
            case .changed:
                // Swipe up = brighter. Full view height ≈ 6 EV of travel.
                let translation = gr.translation(in: view).y
                let delta = Float(-translation / view.bounds.height) * 6.0
                // Quantize to 1/3-stop increments.
                let target = (accumulatedEV + delta)
                let quantized = (target * 3).rounded() / 3
                camera.setExposureBias(quantized)
            default:
                break
            }
        }
    }
}
