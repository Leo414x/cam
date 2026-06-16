import CoreImage
import Foundation

/// A complete "film style" preset. Carries every parameter the pipeline needs:
/// the data that is baked into the procedural 3D LUT (calibration, HSL shifts,
/// saturation, split toning, tone curve, monochrome) plus the spatial filter
/// parameters that run after the LUT (`LeicaFilters`).
struct LeicaStyle: Identifiable, Equatable {
    let id: String
    let name: String          // short label (used in the picker)
    let displayName: String   // full name

    // LUT generation -----------------------------------------------------
    /// Per-band HSL shifts (8 Lightroom-style bands). Empty for monochrome.
    let hslShifts: [(hueShift: Float, satMult: Float, lumOffset: Float)]
    let globalSaturation: Float       // multiplier (1.0 = no change)
    let calibrationR: Float           // red primary shift
    let calibrationG: Float           // green primary shift
    let calibrationB: Float           // blue primary shift

    // Split toning -------------------------------------------------------
    let highlightTintHue: Float       // 0...1 hue wheel
    let highlightTintSat: Float       // 0...1
    let highlightTintStrength: Float  // 0...1
    let shadowTintHue: Float
    let shadowTintSat: Float
    let shadowTintStrength: Float

    // Tone curve (baked into LUT) ----------------------------------------
    let toneCurvePoints: [(Float, Float)]

    // Spatial filters (run after the LUT) --------------------------------
    let microContrast: MicroContrastParams
    let grain: GrainParams
    let vignette: VignetteParams
    let halation: HalationParams

    // White balance ------------------------------------------------------
    let whiteBalanceShiftKelvin: Float  // added to auto WB (warm > 0)

    // Monochrome ---------------------------------------------------------
    let isMonochrome: Bool
    let monochromeWeights: (r: Float, g: Float, b: Float)?

    static func == (lhs: LeicaStyle, rhs: LeicaStyle) -> Bool { lhs.id == rhs.id }
}
