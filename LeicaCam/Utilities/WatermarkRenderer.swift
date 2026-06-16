import UIKit

/// Renders a tasteful EXIF-style watermark ("28mm  ƒ/1.4  Summilux") onto a
/// captured image. Off by default; toggled from the review screen.
enum WatermarkRenderer {

    /// 35mm-equivalent focal length label for the lens that was used.
    static func focalLengthLabel(for lens: LensKind) -> String {
        switch lens {
        case .ultraWide: return "13mm"
        case .wide:      return "28mm"
        case .telephoto: return "77mm"
        }
    }

    enum LensKind { case ultraWide, wide, telephoto }

    /// Draw the watermark in the bottom-right corner and return a new image.
    static func apply(to image: UIImage, lens: LensKind = .wide) -> UIImage {
        let text = "\(focalLengthLabel(for: lens))   ƒ/1.4   Summilux"
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { _ in
            image.draw(at: .zero)

            // Scale font to the image's longest edge so it reads the same on
            // any resolution (~1.6% of the long edge).
            let fontSize = max(11, min(image.size.width, image.size.height) * 0.016)
            let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributed.size()
            let margin = fontSize * 1.4
            let origin = CGPoint(x: image.size.width - textSize.width - margin,
                                 y: image.size.height - textSize.height - margin)
            attributed.draw(at: origin)
        }
    }
}
