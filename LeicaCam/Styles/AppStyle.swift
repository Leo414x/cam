import Foundation

/// A selectable style in the picker. Wraps the kinds the pipeline supports so the
/// camera, picker and pipeline can treat them uniformly while each kind keeps its
/// own model and processing path.
enum AppStyle: Identifiable, Equatable {
    case leica(LeicaStyle)
    case dazz(DazzSingleLUTStyle)
    case dazzRetro(DazzRetroPolaroidPreset)

    var id: String {
        switch self {
        case .leica(let s): return s.id
        case .dazz(let s): return s.id
        case .dazzRetro(let p): return p.id
        }
    }

    /// Short label for the picker pill.
    var name: String {
        switch self {
        case .leica(let s): return s.name
        case .dazz(let s): return s.name
        case .dazzRetro(let p): return p.code      // "PO1"
        }
    }

    var displayName: String {
        switch self {
        case .leica(let s): return s.displayName
        case .dazz(let s): return s.displayName
        case .dazzRetro(let p): return p.name      // "Polaroid 1"
        }
    }

    /// Section key — the picker draws a divider whenever this changes between
    /// consecutive styles.
    var groupKey: String {
        switch self {
        case .leica: return "leica"
        case .dazz: return "dazz"
        case .dazzRetro: return "polaroid"
        }
    }

    static func == (lhs: AppStyle, rhs: AppStyle) -> Bool { lhs.id == rhs.id }
}

/// The full ordered list shown in the picker: Leica procedural styles, then the
/// Dazz/Kuji LUT styles, then the Polaroid retro pack.
enum AppStyleLibrary {
    static let all: [AppStyle] =
        StyleLibrary.all.map(AppStyle.leica)
        + DazzLibrary.all.map(AppStyle.dazz)
        + DazzRetroLibrary.all.map(AppStyle.dazzRetro)

    static var `default`: AppStyle { .leica(StyleLibrary.default) }
}
