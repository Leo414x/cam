import Foundation

/// Style-adjustment layer for a Dazz Retro preset. Ranges follow
/// `style_parameter_defaults_v3_2_2.csv`:
/// brightness −1…1 (0), contrast 0…4 (1), saturation 0…5 (1), sharpen 0…10 (0),
/// exposure −1…1 (0), wb temp −1…1 (0), wb tint 0…5 (**1 = neutral**),
/// shadows/highlights −1…1 (0), vignette 0…1, grain 0…1.
struct DazzRetroStyleAdjustments: Codable, Hashable {
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var sharpen: Float
    var exposure: Float
    var whiteBalanceTemperature: Float
    var whiteBalanceTint: Float
    var shadows: Float
    var highlights: Float
    var vignette: Float
    var grain: Float

    /// Manifest default style for the Polaroid presets (color comes from the LUT;
    /// vignette/grain give the print character).
    static let polaroidDefault = DazzRetroStyleAdjustments(
        brightness: 0, contrast: 1, saturation: 1, sharpen: 0, exposure: 0,
        whiteBalanceTemperature: 0, whiteBalanceTint: 1, shadows: 0, highlights: 0,
        vignette: 0.18, grain: 0.14)
}

/// Texture-layer settings. `frameMask*` is modeled but deferred (no frame
/// compositing path in the app yet — see `DazzRetroProcessor`).
struct DazzRetroTextureSettings: Codable, Hashable {
    var dustResourceName: String?
    var dustIntensity: Float
    var lightLeakResourceName: String?
    var lightLeakIntensity: Float
    var frameMaskResourceName: String?
    var frameIntensity: Float
}

/// One Polaroid preset: a 512 LUT + style adjustments + textures. `style`,
/// `textures` and `lutIntensity` are `var` so the debug edit panel can tune them
/// live; identity (`id`/`code`/`name`/`lutResourceName`) is fixed.
struct DazzRetroPolaroidPreset: Identifiable, Codable, Hashable {
    let id: String
    let code: String
    let name: String
    let lutResourceName: String
    var lutIntensity: Float
    var style: DazzRetroStyleAdjustments
    var textures: DazzRetroTextureSettings
}

extension DazzRetroPolaroidPreset {
    /// Builds a Polaroid preset from the manifest convention. `leak` is the
    /// per-preset light-leak intensity (0 for PO5/PO6/PO8).
    static func polaroid(_ n: Int, leak: Float) -> DazzRetroPolaroidPreset {
        DazzRetroPolaroidPreset(
            id: "dazz-retro-polaroid-\(n)",
            code: "PO\(n)",
            name: "Polaroid \(n)",
            lutResourceName: "lookup_polaroid_\(n)",
            lutIntensity: 1.0,
            style: .polaroidDefault,
            textures: DazzRetroTextureSettings(
                dustResourceName: "dust_\(n)", dustIntensity: 0.1,
                lightLeakResourceName: "leak_\(n)", lightLeakIntensity: leak,
                frameMaskResourceName: "mask_\(n)", frameIntensity: 0))
    }
}

/// The 8 bundled Polaroid presets (light-leak amounts per the manifest).
enum DazzRetroLibrary {
    static let all: [DazzRetroPolaroidPreset] = [
        .polaroid(1, leak: 0.12), .polaroid(2, leak: 0.12),
        .polaroid(3, leak: 0.12), .polaroid(4, leak: 0.12),
        .polaroid(5, leak: 0.0),  .polaroid(6, leak: 0.0),
        .polaroid(7, leak: 0.12), .polaroid(8, leak: 0.0),
    ]

    /// The fresh preset (manifest defaults) for a given id — used by the edit
    /// panel's Reset.
    static func defaults(forID id: String) -> DazzRetroPolaroidPreset? {
        all.first { $0.id == id }
    }
}
