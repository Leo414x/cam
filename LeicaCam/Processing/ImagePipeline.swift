import CoreImage

/// Orchestrates the full Leica filter chain. The same instance is used for the
/// lightweight live-preview path and the full-quality capture path.
final class ImagePipeline {

    /// Procedural LUTs are cached inside `LUTFilter`, so building one per call
    /// is cheap.
    private func lut(for style: LeicaStyle) -> LUTFilter {
        LUTFilter.procedural(style.lutKind)
    }

    /// Live preview: cheaper subset (steps 1, 2, 5, 7 — plus mono conversion).
    /// Skips micro-contrast, highlight rolloff and grain to hold frame rate.
    func processPreview(_ input: CIImage, style: LeicaStyle) -> CIImage {
        var image = input
        image = LeicaFilters.warmShift(image)                       // 1
        image = lut(for: style).apply(to: image)                    // 2
        if style.isMonochrome {
            image = LeicaFilters.monochrome(image, tint: style.monochromeTint)
        } else {
            image = LeicaFilters.splitTone(image,                   // 5
                                           highlightWarmth: style.highlightWarmth,
                                           shadowCoolness: style.shadowCoolness)
        }
        image = LeicaFilters.vignette(image, intensity: style.vignetteIntensity) // 7
        return image.cropped(to: input.extent)
    }

    /// Full capture: every step at full resolution.
    func processCapture(_ input: CIImage, style: LeicaStyle) -> CIImage {
        var image = input
        image = LeicaFilters.warmShift(image)                                       // 1
        image = lut(for: style).apply(to: image)                                    // 2
        image = LeicaFilters.microContrast(image, amount: style.microContrastAmount) // 3
        image = LeicaFilters.highlightRolloff(image, amount: style.highlightRolloff) // 4
        if style.isMonochrome {
            image = LeicaFilters.monochrome(image, tint: style.monochromeTint)
        } else {
            image = LeicaFilters.splitTone(image,                                   // 5
                                           highlightWarmth: style.highlightWarmth,
                                           shadowCoolness: style.shadowCoolness)
        }
        image = LeicaFilters.filmGrain(image, amount: style.grainAmount)            // 6
        image = LeicaFilters.vignette(image, intensity: style.vignetteIntensity)    // 7
        return image.cropped(to: input.extent)                                      // 8
    }
}
