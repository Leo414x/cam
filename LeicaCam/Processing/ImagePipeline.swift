import CoreImage

/// Orchestrates the filter chain for the selected style. Leica styles use a
/// procedural cube plus spatial filters; Dazz styles use a single bundled LUT.
/// The `AppStyle` switch keeps both paths separate while the camera and UI treat
/// styles uniformly.
final class ImagePipeline {

    // MARK: - Entry points (dispatch on style kind)

    /// Live preview (real-time).
    func processPreview(_ input: CIImage, style: AppStyle) -> CIImage {
        switch style {
        case .leica(let s):     return processLeicaPreview(input, style: s)
        case .dazz(let s):      return processDazz(input, style: s)
        case .dazzRetro(let p): return DazzRetroProcessor.shared.process(input, preset: p)
        }
    }

    /// Full-quality capture path.
    func processCapture(_ input: CIImage, style: AppStyle) -> CIImage {
        switch style {
        case .leica(let s):     return processLeicaCapture(input, style: s)
        case .dazz(let s):      return processDazz(input, style: s)
        // Polaroid uses the SAME full chain for preview and export (parity).
        case .dazzRetro(let p): return DazzRetroProcessor.shared.process(input, preset: p)
        }
    }

    // MARK: - Dazz (single bundled LUT)

    /// Preview and export use the SAME path: just the LUT (cube data is cached).
    private func processDazz(_ input: CIImage, style: DazzSingleLUTStyle) -> CIImage {
        guard let out = try? DazzLUTFilter.shared.applyDazzLUT(input, style: style, intensity: 1.0) else {
            return input   // never produce blank output on failure
        }
        return out.cropped(to: input.extent)
    }

    // MARK: - Leica (procedural cube + spatial filters)

    /// Procedural LUTs are cached by style id inside `LUTFilter`.
    private func lut(for style: LeicaStyle) -> LUTFilter {
        LUTFilter.procedural(for: style)
    }

    /// Live preview: LUT → micro-contrast → vignette. micro-contrast now runs in
    /// preview too (with the same resolution-scaled radii) so the preview matches
    /// the capture. Halation and grain are still skipped to hold frame rate.
    private func processLeicaPreview(_ input: CIImage, style: LeicaStyle) -> CIImage {
        var image = input
        image = lut(for: style).apply(to: image)                 // 3D LUT color grading
        image = LeicaFilters.microContrast(image, params: style.microContrast)
        image = LeicaFilters.vignette(image, params: style.vignette)
        return image.cropped(to: input.extent)
    }

    /// Full-quality capture (per the spec's processing order):
    /// WB shift → LUT → micro-contrast → halation → grain → vignette → output.
    private func processLeicaCapture(_ input: CIImage, style: LeicaStyle) -> CIImage {
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
