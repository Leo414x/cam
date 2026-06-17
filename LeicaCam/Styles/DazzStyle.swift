import Foundation

/// A LUT-based style extracted from the Dazz/Kuji style set. Unlike `LeicaStyle`
/// (which generates its cube procedurally), a Dazz style is driven entirely by a
/// baked LUT image bundled with the app. The fitted parameters from the CSV are
/// intentionally NOT modeled here — for the MVP the LUT is the source of truth.
struct DazzSingleLUTStyle: Hashable, Identifiable {
    let id: String
    let code: String
    let name: String
    let displayName: String
    let category: String
    /// Bundle resource name (without extension) of the 256×16 LUT strip.
    let lutResourceName: String
    /// Hint that this LUT renders a near-monochrome look (UI / future use).
    let isMonochromeLike: Bool
}

extension DazzSingleLUTStyle {
    /// The single style implemented in this first pass. Source LUT:
    /// `f_villau2z.png` (256×16 strip → 16³ cube).
    static let kuji = DazzSingleLUTStyle(
        id: "dazz-kj",
        code: "KJ",
        name: "Kuji",
        displayName: "Dazz Kuji",
        category: "Default",
        lutResourceName: "f_villau2z",
        isMonochromeLike: false
    )
}

/// Catalogue of bundled Dazz styles. Only one is imported in this pass; the
/// remaining ~128 are deliberately left out until this path is verified.
enum DazzLibrary {
    static let all: [DazzSingleLUTStyle] = [.kuji]
}
