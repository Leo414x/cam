import CoreImage
import Foundation

/// The built-in catalogue of Leica-inspired styles.
enum StyleLibrary {
    static let all: [LeicaStyle] = [classic, monochrom, contemporary]

    static var `default`: LeicaStyle { classic }

    /// "Classic" — warm, rich midtones. Leica M + Summilux on Kodak Portra.
    static let classic = LeicaStyle(
        id: "classic",
        name: "classic",
        displayName: "Classic",
        lutKind: .classic,
        microContrastAmount: 0.40,
        grainAmount: 0.08,
        vignetteIntensity: 0.35,
        highlightWarmth: 0.55,
        shadowCoolness: 0.30,
        highlightRolloff: 0.6,
        isMonochrome: false,
        monochromeTint: nil
    )

    /// "Monochrom" — true B&W with deep blacks and creamy highlights.
    static let monochrom = LeicaStyle(
        id: "monochrom",
        name: "monochrom",
        displayName: "Monochrom",
        lutKind: .monochrom,
        microContrastAmount: 0.50,
        grainAmount: 0.12,
        vignetteIntensity: 0.40,
        highlightWarmth: 0.0,
        shadowCoolness: 0.0,
        highlightRolloff: 0.7,
        isMonochrome: true,
        // A barely-there cool selenium tone keeps the blacks from feeling flat.
        monochromeTint: CIColor(red: 0.92, green: 0.94, blue: 1.0)
    )

    /// "Contemporary" — cleaner, slightly cooler, modern digital Leica.
    static let contemporary = LeicaStyle(
        id: "contemporary",
        name: "contemporary",
        displayName: "Contemporary",
        lutKind: .contemporary,
        microContrastAmount: 0.30,
        grainAmount: 0.04,
        vignetteIntensity: 0.25,
        highlightWarmth: 0.20,
        shadowCoolness: 0.35,
        highlightRolloff: 0.45,
        isMonochrome: false,
        monochromeTint: nil
    )
}
