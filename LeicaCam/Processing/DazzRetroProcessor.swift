import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Full Dazz Retro Polaroid effect pipeline:
/// `1. base → 2. LUT → 3. style adjustments → 4. textures → 5. output`.
/// The same call is used for preview and export (parity); `applyStyle` /
/// `applyTextures` can be turned off for LUT-only A/B testing.
final class DazzRetroProcessor {
    static let shared = DazzRetroProcessor()
    private init() {}

    private enum Blend { case lighten, colorDodge }

    private var textureCache: [String: CIImage] = [:]
    private let cacheQueue = DispatchQueue(label: "dazzretro.texture.cache")
    private lazy var renderContext = CIContext()

    // MARK: - Main pipeline

    func process(_ input: CIImage,
                 preset: DazzRetroPolaroidPreset,
                 applyStyle: Bool = true,
                 applyTextures: Bool = true) -> CIImage {
        let extent = input.extent
        var image = input

        // 2. LUT layer (512 atlas, cached).
        image = DazzRetroLUTFilter.shared.apply(image,
                                                resourceName: preset.lutResourceName,
                                                intensity: preset.lutIntensity)
        // 3. Style adjustment layer.
        if applyStyle { image = styleLayer(image, preset.style) }
        // 4. Texture / filter layer.
        if applyTextures { image = textureLayer(image, preset, extent: extent) }

        return image.cropped(to: extent)
    }

    /// Convenience for the demo screen: process a still and rasterize.
    func processSample(_ uiImage: UIImage,
                       preset: DazzRetroPolaroidPreset,
                       applyStyle: Bool,
                       applyTextures: Bool) -> UIImage? {
        guard let cg = uiImage.cgImage else { return nil }
        let out = process(CIImage(cgImage: cg), preset: preset,
                          applyStyle: applyStyle, applyTextures: applyTextures)
        guard let rendered = renderContext.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }

    // MARK: - 3. Style adjustment layer

    private func styleLayer(_ input: CIImage, _ s: DazzRetroStyleAdjustments) -> CIImage {
        var image = input

        if s.exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = s.exposure * 2          // −1…1 → ±2 stops
            image = f.outputImage ?? image
        }
        if s.whiteBalanceTemperature != 0 || s.whiteBalanceTint != 1 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            // temp > 0 = warmer (lower target K); tint baseline is 1 (neutral).
            f.targetNeutral = CIVector(x: CGFloat(6500 - s.whiteBalanceTemperature * 1500),
                                       y: CGFloat((s.whiteBalanceTint - 1) * 50))
            image = f.outputImage ?? image
        }
        if s.brightness != 0 || s.contrast != 1 || s.saturation != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.brightness = s.brightness
            f.contrast = s.contrast
            f.saturation = s.saturation
            image = f.outputImage ?? image
        }
        if s.shadows != 0 || s.highlights != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.shadowAmount = max(-1, min(1, s.shadows))           // >0 lifts shadows
            f.highlightAmount = max(0, min(1, 1 - max(0, s.highlights)))  // <1 pulls highlights
            image = f.outputImage ?? image
        }
        if s.sharpen > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = s.sharpen * 0.1                          // 0…10 → 0…1
            image = f.outputImage ?? image
        }
        return image
    }

    // MARK: - 4. Texture / filter layer

    private func textureLayer(_ input: CIImage,
                              _ preset: DazzRetroPolaroidPreset,
                              extent: CGRect) -> CIImage {
        var image = input
        let tx = preset.textures

        if let name = tx.dustResourceName, tx.dustIntensity > 0 {
            image = blendTexture(name, over: image, extent: extent,
                                 mode: .colorDodge, intensity: tx.dustIntensity)
        }
        if let name = tx.lightLeakResourceName, tx.lightLeakIntensity > 0 {
            image = blendTexture(name, over: image, extent: extent,
                                 mode: .lighten, intensity: tx.lightLeakIntensity)
        }
        if preset.style.vignette > 0 {
            image = vignette(image, intensity: preset.style.vignette, extent: extent)
        }
        if preset.style.grain > 0 {
            image = LeicaFilters.filmGrain(image, params: GrainParams(
                amount: preset.style.grain, size: 1.2, roughness: 0.5, luminanceOnly: true))
        }
        // Frame/mask is modeled (`tx.frameMaskResourceName`) but not rendered:
        // the app has no frame-compositing path yet, so it is deferred.
        return image
    }

    private func blendTexture(_ name: String, over base: CIImage, extent: CGRect,
                              mode: Blend, intensity: Float) -> CIImage {
        guard let tex = texture(named: name) else { return base }
        let scaled = scaleToCover(tex, extent: extent)

        let blended: CIImage
        switch mode {
        case .lighten:
            let f = CIFilter.lightenBlendMode()
            f.inputImage = scaled; f.backgroundImage = base
            blended = f.outputImage ?? base
        case .colorDodge:
            let f = CIFilter.colorDodgeBlendMode()
            f.inputImage = scaled; f.backgroundImage = base
            blended = f.outputImage ?? base
        }
        // mix(base, blended, intensity): fade the blended layer over the base.
        let t = max(0, min(1, intensity))
        let faded = blended.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(t))
        ])
        return faded.composited(over: base).cropped(to: extent)
    }

    private func vignette(_ image: CIImage, intensity: Float, extent: CGRect) -> CIImage {
        let f = CIFilter.vignetteEffect()
        f.inputImage = image
        f.center = CGPoint(x: extent.midX, y: extent.midY)
        let diag = (extent.width * extent.width + extent.height * extent.height).squareRoot()
        f.radius = Float(diag) * 0.5 * 0.95
        f.intensity = intensity * 1.2
        f.falloff = 0.5
        return f.outputImage ?? image
    }

    // MARK: - Texture loading / caching

    private func texture(named name: String) -> CIImage? {
        cacheQueue.sync {
            if let cached = textureCache[name] { return cached }
            guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
                  let img = UIImage(contentsOfFile: url.path),
                  let cg = img.cgImage else { return nil }
            let ci = CIImage(cgImage: cg)
            textureCache[name] = ci
            return ci
        }
    }

    /// Aspect-fill the texture over `extent`, centered.
    private func scaleToCover(_ tex: CIImage, extent: CGRect) -> CIImage {
        let te = tex.extent
        guard te.width > 0, te.height > 0 else { return tex }
        let scale = max(extent.width / te.width, extent.height / te.height)
        let scaled = tex.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let dx = extent.midX - scaled.extent.midX
        let dy = extent.midY - scaled.extent.midY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: extent)
    }
}
