import CoreImage
import CoreImage.CIFilterBuiltins

/// Stateless Core Image building blocks for the Leica look. Each function takes
/// a `CIImage` and returns a `CIImage`; they are composed by `ImagePipeline`.
enum LeicaFilters {

    // MARK: - 1. Warm white-balance shift --------------------------------

    /// A subtle, predictable warm bias (~+200K feel) via a channel matrix.
    static func warmShift(_ image: CIImage, amount: Float = 1.0) -> CIImage {
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: CGFloat(1.0 + 0.03 * amount), y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: CGFloat(1.0 + 0.005 * amount), z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: CGFloat(1.0 - 0.02 * amount), w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return f.outputImage ?? image
    }

    // MARK: - 2. Micro-contrast (Clarity) --------------------------------

    /// Mid-frequency local-contrast boost. Unsharp mask is exactly
    /// `original + amount·(original − blur)`, with a large radius for "clarity"
    /// rather than edge sharpening. This is the key "3D pop" differentiator.
    static func microContrast(_ image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        let f = CIFilter.unsharpMask()
        f.inputImage = image
        f.radius = 18.0
        f.intensity = amount        // 0.3...0.5 typical
        return f.outputImage ?? image
    }

    // MARK: - 3. Highlight rolloff ---------------------------------------

    /// Film-like highlight shoulder via a tone curve. `amount` blends between
    /// the identity curve and the fully-compressed curve.
    static func highlightRolloff(_ image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        let a = CGFloat(min(1, max(0, amount)))
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            // lerp the y toward the compressed target by `a`
            CGPoint(x: x, y: x + (y - x) * a)
        }
        let f = CIFilter.toneCurve()
        f.inputImage = image
        f.point0 = p(0.00, 0.00)
        f.point1 = p(0.25, 0.28)
        f.point2 = p(0.50, 0.55)
        f.point3 = p(0.75, 0.82)
        f.point4 = p(1.00, 0.95)
        return f.outputImage ?? image
    }

    // MARK: - 4. Split toning --------------------------------------------

    /// Warm highlights / cool shadows, blended by a luminance mask so the tint
    /// only lands where it should.
    static func splitTone(_ image: CIImage, highlightWarmth: Float, shadowCoolness: Float) -> CIImage {
        guard highlightWarmth > 0 || shadowCoolness > 0 else { return image }

        // Luminance mask: white = highlights.
        let mask = CIFilter.colorControls()
        mask.inputImage = image
        mask.saturation = 0
        guard let lumaMask = mask.outputImage else { return image }

        let w = CGFloat(highlightWarmth)
        let warm = CIFilter.colorMatrix()
        warm.inputImage = image
        warm.rVector = CIVector(x: 1 + 0.06 * w, y: 0, z: 0, w: 0)
        warm.gVector = CIVector(x: 0, y: 1 + 0.02 * w, z: 0, w: 0)
        warm.bVector = CIVector(x: 0, y: 0, z: 1 - 0.04 * w, w: 0)
        warm.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let c = CGFloat(shadowCoolness)
        let cool = CIFilter.colorMatrix()
        cool.inputImage = image
        cool.rVector = CIVector(x: 1 - 0.03 * c, y: 0, z: 0, w: 0)
        cool.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        cool.bVector = CIVector(x: 0, y: 0, z: 1 + 0.05 * c, w: 0)
        cool.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        guard let warmImg = warm.outputImage, let coolImg = cool.outputImage else { return image }

        // warm where mask is bright (highlights), cool where mask is dark.
        let blend = CIFilter.blendWithMask()
        blend.inputImage = warmImg          // shown where mask is white
        blend.backgroundImage = coolImg     // shown where mask is black
        blend.maskImage = lumaMask
        return blend.outputImage ?? image
    }

    // MARK: - 5. Film grain ----------------------------------------------

    /// Monochromatic luminance grain that fades out in the highlights, blended
    /// over the image at low opacity.
    static func filmGrain(_ image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty else { return image }

        // Random colored noise -> desaturate -> centre around mid-grey.
        guard let noiseGen = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let mono = CIFilter.colorControls()
        mono.inputImage = noiseGen
        mono.saturation = 0
        mono.contrast = 1.0
        // Scale noise so grain is ~1.5px at output resolution.
        guard let monoImg = mono.outputImage else { return image }
        let scaled = monoImg.transformed(by: CGAffineTransform(scaleX: 1.5, y: 1.5))
                            .cropped(to: extent)

        // Highlights mask: less grain where the image is bright (realistic film).
        let lumaCtrl = CIFilter.colorControls()
        lumaCtrl.inputImage = image
        lumaCtrl.saturation = 0
        // invert so shadows = white (more grain)
        let inv = CIFilter.colorInvert()
        inv.inputImage = lumaCtrl.outputImage
        let grainMask = inv.outputImage ?? scaled

        // Apply grain opacity.
        let opacity = CGFloat(min(0.18, amount * 0.18))
        let alpha = CIFilter.colorMatrix()
        alpha.inputImage = scaled
        alpha.aVector = CIVector(x: 0, y: 0, z: 0, w: opacity)
        guard let grainLayer = alpha.outputImage else { return image }

        // Modulate grain by the highlight mask.
        let masked = CIFilter.blendWithMask()
        masked.inputImage = grainLayer
        masked.backgroundImage = CIImage(color: .clear).cropped(to: extent)
        masked.maskImage = grainMask
        let modulated = masked.outputImage ?? grainLayer

        // Overlay grain using a soft-light style blend for a film feel.
        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = modulated
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    // MARK: - 6. Natural vignette ----------------------------------------

    static func vignette(_ image: CIImage, intensity: Float) -> CIImage {
        guard intensity > 0 else { return image }
        let f = CIFilter.vignetteEffect()
        f.inputImage = image
        let extent = image.extent
        f.center = CGPoint(x: extent.midX, y: extent.midY)
        let diagonal = (extent.width * extent.width + extent.height * extent.height).squareRoot()
        f.radius = Float(diagonal) * 0.42        // smooth, gradual falloff
        f.intensity = intensity * 0.5            // keep it subtle, not Instagram
        f.falloff = 0.5
        return f.outputImage ?? image
    }

    // MARK: - 7. Monochrome conversion -----------------------------------

    /// Weighted-luminance B&W with an optional subtle tint.
    static func monochrome(_ image: CIImage, tint: CIColor?) -> CIImage {
        let mono = CIFilter.colorMatrix()
        mono.inputImage = image
        // Each output channel = luminance (0.3R + 0.59G + 0.11B).
        let l = CIVector(x: 0.30, y: 0.59, z: 0.11, w: 0)
        mono.rVector = l
        mono.gVector = l
        mono.bVector = l
        mono.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard var result = mono.outputImage else { return image }

        if let tint, let multiply = CIFilter(name: "CIMultiplyCompositing") {
            let tintImage = CIImage(color: tint).cropped(to: result.extent)
            multiply.setValue(tintImage, forKey: kCIInputImageKey)
            multiply.setValue(result, forKey: kCIInputBackgroundImageKey)
            result = multiply.outputImage ?? result
        }
        return result
    }
}
