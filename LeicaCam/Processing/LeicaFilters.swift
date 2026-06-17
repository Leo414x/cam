import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Parameter structs (per-style presets)

/// Micro-contrast (clarity): large-radius unsharp masking, luminance-weighted
/// so highlights/shadows get less than midtones (prevents halos, keeps "pop").
struct MicroContrastParams {
    let blurRadius: Float
    let alpha: Float
    let clampMin: Float
    let clampMax: Float

    // alpha = micro-contrast (clarity) strength. Lowered uniformly to ~60% of
    // the original fitted values to tame over-sharpening on full-res captures.
    static let classic      = MicroContrastParams(blurRadius: 20, alpha: 0.24, clampMin: -0.15, clampMax: 0.15)
    static let contemporary = MicroContrastParams(blurRadius: 18, alpha: 0.18, clampMin: -0.12, clampMax: 0.12)
    static let natural      = MicroContrastParams(blurRadius: 16, alpha: 0.12, clampMin: -0.10, clampMax: 0.10)
    static let vivid        = MicroContrastParams(blurRadius: 22, alpha: 0.27, clampMin: -0.18, clampMax: 0.18)
    static let monochrom    = MicroContrastParams(blurRadius: 22, alpha: 0.30, clampMin: -0.20, clampMax: 0.20)
}

/// Film grain: luminance noise that fades out in the highlights.
struct GrainParams {
    let amount: Float
    let size: Float
    let roughness: Float
    let luminanceOnly: Bool

    static let classic      = GrainParams(amount: 0.06, size: 1.2, roughness: 0.55, luminanceOnly: true)
    static let contemporary = GrainParams(amount: 0.03, size: 1.0, roughness: 0.50, luminanceOnly: true)
    static let natural      = GrainParams(amount: 0.04, size: 1.1, roughness: 0.50, luminanceOnly: true)
    static let vivid        = GrainParams(amount: 0.03, size: 1.0, roughness: 0.45, luminanceOnly: true)
    static let monochrom    = GrainParams(amount: 0.10, size: 1.5, roughness: 0.60, luminanceOnly: true)
}

/// Natural lens-falloff vignette (added, not corrected away).
struct VignetteParams {
    let intensity: Float
    let radius: Float   // relative to image diagonal
    let falloff: Float

    static let classic      = VignetteParams(intensity: 0.35, radius: 0.85, falloff: 0.7)
    static let contemporary = VignetteParams(intensity: 0.25, radius: 0.90, falloff: 0.8)
    static let natural      = VignetteParams(intensity: 0.20, radius: 0.90, falloff: 0.8)
    static let vivid        = VignetteParams(intensity: 0.30, radius: 0.85, falloff: 0.7)
    static let monochrom    = VignetteParams(intensity: 0.40, radius: 0.80, falloff: 0.6)
}

/// Highlight halation: gentle warm bloom around bright areas.
struct HalationParams {
    let threshold: Float
    let radius: Float
    let intensity: Float
    let tint: (r: Float, g: Float, b: Float)

    static let classic      = HalationParams(threshold: 0.82, radius: 30, intensity: 0.08, tint: (1.0, 0.95, 0.88))
    static let contemporary = HalationParams(threshold: 0.85, radius: 25, intensity: 0.05, tint: (1.0, 0.97, 0.92))
    static let natural      = HalationParams(threshold: 0.88, radius: 20, intensity: 0.03, tint: (1.0, 0.98, 0.95))
    static let vivid        = HalationParams(threshold: 0.80, radius: 28, intensity: 0.06, tint: (1.0, 0.94, 0.86))
    static let monochrom    = HalationParams(threshold: 0.82, radius: 25, intensity: 0.06, tint: (1.0, 1.0, 1.0))
}

// MARK: - Spatial filters

/// Stateless Core Image building blocks that run AFTER the LUT (they cannot be
/// baked into a 3D LUT because they are spatial).
enum LeicaFilters {

    /// Warm white-balance shift (Kelvin). Positive = warmer.
    static func whiteBalance(_ image: CIImage, kelvinShift: Float) -> CIImage {
        guard abs(kelvinShift) > 0.5 else { return image }
        let f = CIFilter.temperatureAndTint()
        f.inputImage = image
        f.neutral = CIVector(x: 6500, y: 0)
        // Lowering the target temperature warms the rendered white point.
        f.targetNeutral = CIVector(x: CGFloat(6500 - kelvinShift), y: 0)
        return f.outputImage ?? image
    }

    /// Micro-contrast / clarity, luminance-weighted (full only in midtones).
    static func microContrast(_ image: CIImage, params: MicroContrastParams) -> CIImage {
        guard params.alpha > 0 else { return image }

        // Unsharp mask = original + alpha·(original − gaussianBlur).
        let unsharp = CIFilter.unsharpMask()
        unsharp.inputImage = image
        unsharp.radius = params.blurRadius
        unsharp.intensity = params.alpha
        guard let sharp = unsharp.outputImage else { return image }

        // Luminance-zone mask: ~full in mids, reduced in highlights/shadows.
        let luma = CIFilter.colorControls()
        luma.inputImage = image
        luma.saturation = 0
        guard let lumaImg = luma.outputImage else { return sharp }

        let weight = CIFilter.toneCurve()
        weight.inputImage = lumaImg
        weight.point0 = CGPoint(x: 0.00, y: 0.70)   // shadows: −30%
        weight.point1 = CGPoint(x: 0.25, y: 1.00)   // midtones: full
        weight.point2 = CGPoint(x: 0.50, y: 1.00)
        weight.point3 = CGPoint(x: 0.75, y: 1.00)
        weight.point4 = CGPoint(x: 1.00, y: 0.40)   // highlights: −60%
        guard let mask = weight.outputImage else { return sharp }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = sharp
        blend.backgroundImage = image
        blend.maskImage = mask
        return blend.outputImage?.cropped(to: image.extent) ?? sharp
    }

    /// Highlight halation: isolate highlights → blur → warm tint → screen blend.
    static func halation(_ image: CIImage, params: HalationParams) -> CIImage {
        guard params.intensity > 0 else { return image }
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty else { return image }

        // Isolate highlights above threshold and linearly stretch to 0...1.
        let scale = CGFloat(1.0 / max(0.001, 1.0 - params.threshold))
        let bias = CGFloat(-params.threshold) * scale
        let isolate = CIFilter.colorMatrix()
        isolate.inputImage = image
        isolate.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        isolate.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        isolate.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        isolate.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        isolate.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        guard let isolated = isolate.outputImage else { return image }

        let clamp = CIFilter.colorClamp()
        clamp.inputImage = isolated
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = clamp.outputImage
        blur.radius = params.radius
        guard let bloomBlurred = blur.outputImage?.cropped(to: extent) else { return image }

        // Apply warm tint and scale by intensity in one matrix.
        let i = CGFloat(params.intensity)
        let tinted = CIFilter.colorMatrix()
        tinted.inputImage = bloomBlurred
        tinted.rVector = CIVector(x: CGFloat(params.tint.r) * i, y: 0, z: 0, w: 0)
        tinted.gVector = CIVector(x: 0, y: CGFloat(params.tint.g) * i, z: 0, w: 0)
        tinted.bVector = CIVector(x: 0, y: 0, z: CGFloat(params.tint.b) * i, w: 0)
        tinted.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let bloom = tinted.outputImage else { return image }

        let screen = CIFilter.screenBlendMode()
        screen.inputImage = bloom
        screen.backgroundImage = image
        return screen.outputImage?.cropped(to: extent) ?? image
    }

    /// Film grain: scaled luminance noise, fading out in highlights.
    static func filmGrain(_ image: CIImage, params: GrainParams) -> CIImage {
        guard params.amount > 0 else { return image }
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty else { return image }

        guard let noiseGen = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let mono = CIFilter.colorControls()
        mono.inputImage = noiseGen
        mono.saturation = params.luminanceOnly ? 0 : 1
        mono.contrast = 1.0 + params.roughness * 0.4
        guard let monoImg = mono.outputImage else { return image }
        let scaled = monoImg
            .transformed(by: CGAffineTransform(scaleX: CGFloat(params.size), y: CGFloat(params.size)))
            .cropped(to: extent)

        // Highlight falloff mask: grainOpacity = amount·(1 − 0.6·smoothstep(0.6,1,luma)).
        let luma = CIFilter.colorControls()
        luma.inputImage = image
        luma.saturation = 0
        let falloff = CIFilter.toneCurve()
        falloff.inputImage = luma.outputImage
        falloff.point0 = CGPoint(x: 0.0, y: 1.0)
        falloff.point1 = CGPoint(x: 0.6, y: 1.0)
        falloff.point2 = CGPoint(x: 0.8, y: 0.7)
        falloff.point3 = CGPoint(x: 0.9, y: 0.55)
        falloff.point4 = CGPoint(x: 1.0, y: 0.4)
        guard let grainMask = falloff.outputImage else { return image }

        // Grain layer at the configured opacity.
        let alpha = CIFilter.colorMatrix()
        alpha.inputImage = scaled
        alpha.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(params.amount))
        guard let grainLayer = alpha.outputImage else { return image }

        let masked = CIFilter.blendWithMask()
        masked.inputImage = grainLayer
        masked.backgroundImage = CIImage(color: .clear).cropped(to: extent)
        masked.maskImage = grainMask
        let modulated = masked.outputImage ?? grainLayer

        // Soft-light blend so mid-grey noise is tonally neutral.
        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = modulated
        blend.backgroundImage = image
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    /// Natural vignette (subtle, gradual).
    static func vignette(_ image: CIImage, params: VignetteParams) -> CIImage {
        guard params.intensity > 0 else { return image }
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty else { return image }
        let f = CIFilter.vignetteEffect()
        f.inputImage = image
        f.center = CGPoint(x: extent.midX, y: extent.midY)
        let diagonal = (extent.width * extent.width + extent.height * extent.height).squareRoot()
        f.radius = Float(diagonal) * 0.5 * params.radius
        f.intensity = params.intensity
        f.falloff = params.falloff
        return f.outputImage ?? image
    }
}
