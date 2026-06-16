import CoreImage
import Foundation

/// Per-band HSL shift tables (8 Lightroom-style hue bands), one set per style.
/// Hue shift is in normalized turns (degrees/360); saturation is a multiplier;
/// luminance is an additive offset.
enum HSLShiftTable {
    // Band order: Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta.
    static let classic: [(hueShift: Float, satMult: Float, lumOffset: Float)] = [
        (+0.014, 0.92, +0.04),
        (+0.008, 0.95, +0.03),
        (-0.014, 0.88, +0.01),
        (+0.028, 0.80, -0.02),
        (+0.014, 0.85, +0.00),
        (-0.014, 0.85, -0.03),
        (+0.008, 0.95, +0.00),
        (-0.008, 0.92, +0.01),
    ]

    static let contemporary: [(hueShift: Float, satMult: Float, lumOffset: Float)] = [
        (+0.010, 0.94, +0.03),
        (+0.006, 0.96, +0.02),
        (-0.010, 0.92, +0.01),
        (+0.020, 0.85, -0.01),
        (+0.010, 0.88, +0.00),
        (-0.008, 0.90, -0.02),
        (+0.005, 0.96, +0.00),
        (-0.005, 0.94, +0.01),
    ]

    static let natural: [(hueShift: Float, satMult: Float, lumOffset: Float)] = [
        (+0.005, 0.97, +0.02),
        (+0.003, 0.98, +0.01),
        (-0.005, 0.95, +0.00),
        (+0.010, 0.90, -0.01),
        (+0.005, 0.92, +0.00),
        (-0.005, 0.93, -0.01),
        (+0.003, 0.97, +0.00),
        (-0.003, 0.96, +0.00),
    ]

    static let vivid: [(hueShift: Float, satMult: Float, lumOffset: Float)] = [
        (+0.014, 1.05, +0.03),
        (+0.008, 1.03, +0.02),
        (-0.014, 1.00, +0.01),
        (+0.028, 0.90, -0.02),
        (+0.014, 0.95, +0.00),
        (-0.010, 1.05, -0.02),
        (+0.008, 1.02, +0.00),
        (-0.008, 0.98, +0.01),
    ]
}

/// The built-in catalogue of Leica-inspired styles.
enum StyleLibrary {
    static var all: [LeicaStyle] { LeicaStyle.allStyles }
    static var `default`: LeicaStyle { .classic }
}

extension LeicaStyle {
    static let classic = LeicaStyle(
        id: "classic",
        name: "Classic",
        displayName: "Leica Classic",
        hslShifts: HSLShiftTable.classic,
        globalSaturation: 0.90,
        calibrationR: 0.012, calibrationG: 0.005, calibrationB: -0.015,
        highlightTintHue: 0.111, highlightTintSat: 0.08, highlightTintStrength: 0.08,
        shadowTintHue: 0.611, shadowTintSat: 0.06, shadowTintStrength: 0.06,
        toneCurvePoints: [(0, 0.04), (0.15, 0.18), (0.25, 0.28), (0.5, 0.55), (0.75, 0.82), (0.90, 0.92), (1.0, 0.95)],
        microContrast: .classic,
        grain: .classic,
        vignette: .classic,
        halation: .classic,
        whiteBalanceShiftKelvin: 250,
        isMonochrome: false,
        monochromeWeights: nil
    )

    static let contemporary = LeicaStyle(
        id: "contemporary",
        name: "Contemporary",
        displayName: "Leica Contemporary",
        hslShifts: HSLShiftTable.contemporary,
        globalSaturation: 0.93,
        calibrationR: 0.008, calibrationG: 0.003, calibrationB: -0.010,
        highlightTintHue: 0.111, highlightTintSat: 0.05, highlightTintStrength: 0.05,
        shadowTintHue: 0.611, shadowTintSat: 0.04, shadowTintStrength: 0.04,
        toneCurvePoints: [(0, 0.03), (0.15, 0.17), (0.25, 0.27), (0.5, 0.53), (0.75, 0.80), (0.90, 0.93), (1.0, 0.96)],
        microContrast: .contemporary,
        grain: .contemporary,
        vignette: .contemporary,
        halation: .contemporary,
        whiteBalanceShiftKelvin: 150,
        isMonochrome: false,
        monochromeWeights: nil
    )

    static let natural = LeicaStyle(
        id: "natural",
        name: "Natural",
        displayName: "Leica Natural",
        hslShifts: HSLShiftTable.natural,
        globalSaturation: 0.95,
        calibrationR: 0.005, calibrationG: 0.002, calibrationB: -0.005,
        highlightTintHue: 0.111, highlightTintSat: 0.03, highlightTintStrength: 0.03,
        shadowTintHue: 0.611, shadowTintSat: 0.02, shadowTintStrength: 0.02,
        toneCurvePoints: [(0, 0.02), (0.15, 0.15), (0.25, 0.26), (0.5, 0.52), (0.75, 0.78), (0.90, 0.92), (1.0, 0.97)],
        microContrast: .natural,
        grain: .natural,
        vignette: .natural,
        halation: .natural,
        whiteBalanceShiftKelvin: 100,
        isMonochrome: false,
        monochromeWeights: nil
    )

    static let vivid = LeicaStyle(
        id: "vivid",
        name: "Vivid",
        displayName: "Leica Vivid",
        hslShifts: HSLShiftTable.vivid,
        globalSaturation: 1.03,
        calibrationR: 0.015, calibrationG: 0.005, calibrationB: -0.012,
        highlightTintHue: 0.111, highlightTintSat: 0.06, highlightTintStrength: 0.06,
        shadowTintHue: 0.611, shadowTintSat: 0.05, shadowTintStrength: 0.05,
        toneCurvePoints: [(0, 0.03), (0.15, 0.16), (0.25, 0.29), (0.5, 0.56), (0.75, 0.84), (0.90, 0.93), (1.0, 0.94)],
        microContrast: .vivid,
        grain: .vivid,
        vignette: .vivid,
        halation: .vivid,
        whiteBalanceShiftKelvin: 200,
        isMonochrome: false,
        monochromeWeights: nil
    )

    static let monochrom = LeicaStyle(
        id: "monochrom",
        name: "Monochrom",
        displayName: "Leica Monochrom",
        hslShifts: [],
        globalSaturation: 0.0,
        calibrationR: 0, calibrationG: 0, calibrationB: 0,
        highlightTintHue: 0, highlightTintSat: 0, highlightTintStrength: 0,
        shadowTintHue: 0, shadowTintSat: 0, shadowTintStrength: 0,
        toneCurvePoints: [(0, 0.02), (0.15, 0.14), (0.25, 0.27), (0.5, 0.56), (0.75, 0.83), (0.90, 0.92), (1.0, 0.95)],
        microContrast: .monochrom,
        grain: .monochrom,
        vignette: .monochrom,
        halation: .monochrom,
        whiteBalanceShiftKelvin: 0,
        isMonochrome: true,
        monochromeWeights: (r: 0.35, g: 0.50, b: 0.15)
    )

    static let allStyles: [LeicaStyle] = [.classic, .contemporary, .natural, .vivid, .monochrom]
}
