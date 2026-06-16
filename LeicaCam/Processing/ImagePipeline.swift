import CoreImage

/// Orchestrates the Leica filter chain. The 3D LUT carries all per-pixel color
/// math (calibration → HSL → saturation → split tone → tone curve, or the
/// monochrome conversion); the spatial filters run after it.
final class ImagePipeline {

    /// Procedural LUTs are cached by style id inside `LUTFilter`.
    private func lut(for style: LeicaStyle) -> LUTFilter {
        LUTFilter.procedural(for: style)
    }

    /// Live preview (real-time): LUT + vignette only. The LUT alone carries the
    /// bulk of the visual character at preview resolution; micro-contrast,
    /// halation and grain are skipped to hold frame rate.
    func processPreview(_ input: CIImage, style: LeicaStyle) -> CIImage {
        var image = input
        image = lut(for: style).apply(to: image)                 // 3D LUT color grading
        image = LeicaFilters.vignette(image, params: style.vignette)
        return image.cropped(to: input.extent)
    }

    /// Full-quality capture path (per the spec's processing order):
    /// WB shift → LUT → micro-contrast → halation → grain → vignette → output.
    func processCapture(_ input: CIImage, style: LeicaStyle) -> CIImage {
        var image = input
        image = LeicaFilters.whiteBalance(image, kelvinShift: style.whiteBalanceShiftKelvin)
        image = lut(for: style).apply(to: image)
        image = LeicaFilters.microContrast(image, params: style.microContrast)
        image = LeicaFilters.halation(image, params: style.halation)
        image = LeicaFilters.filmGrain(image, params: style.grain)
        image = LeicaFilters.vignette(image, params: style.vignette)
        return image.cropped(to: input.extent)
    }
}
