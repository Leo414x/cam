import CoreImage
import Foundation

/// A "film style" preset. Bundles a procedurally-generated 3D LUT together with
/// the post-processing parameters that define the look.
struct LeicaStyle: Identifiable, Equatable {
    let id: String
    let name: String        // short internal name
    let displayName: String // shown in the UI pill

    // Color grading -------------------------------------------------------
    /// Lazily-built procedural LUT for this style. Built once and cached.
    let lutKind: LUTFilter.Kind

    // Post-processing parameters -----------------------------------------
    let microContrastAmount: Float   // 0...1   (Clarity / unsharp intensity)
    let grainAmount: Float           // 0...1
    let vignetteIntensity: Float     // 0...1
    let highlightWarmth: Float       // 0...1   split-tone highlight strength
    let shadowCoolness: Float        // 0...1   split-tone shadow strength
    let highlightRolloff: Float      // 0...1   how much to compress highlights

    // Monochrome ----------------------------------------------------------
    let isMonochrome: Bool
    /// Optional tint applied to a B&W conversion (e.g. selenium / sepia).
    let monochromeTint: CIColor?

    static func == (lhs: LeicaStyle, rhs: LeicaStyle) -> Bool { lhs.id == rhs.id }
}
