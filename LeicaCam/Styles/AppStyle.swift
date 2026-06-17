import Foundation

/// A selectable style in the picker. Wraps the two kinds the pipeline supports
/// so the camera, picker and pipeline can treat them uniformly while each kind
/// keeps its own model and processing path.
enum AppStyle: Identifiable, Equatable {
    case leica(LeicaStyle)
    case dazz(DazzSingleLUTStyle)

    var id: String {
        switch self {
        case .leica(let s): return s.id
        case .dazz(let s): return s.id
        }
    }

    /// Short label for the picker pill.
    var name: String {
        switch self {
        case .leica(let s): return s.name
        case .dazz(let s): return s.name
        }
    }

    var displayName: String {
        switch self {
        case .leica(let s): return s.displayName
        case .dazz(let s): return s.displayName
        }
    }

    /// True for Dazz LUT styles — used by the picker to draw a section divider.
    var isDazz: Bool {
        if case .dazz = self { return true }
        return false
    }

    static func == (lhs: AppStyle, rhs: AppStyle) -> Bool { lhs.id == rhs.id }
}

/// The full ordered list shown in the picker: Leica procedural styles first,
/// then the bundled Dazz LUT styles.
enum AppStyleLibrary {
    static let all: [AppStyle] =
        StyleLibrary.all.map(AppStyle.leica) + DazzLibrary.all.map(AppStyle.dazz)

    static var `default`: AppStyle { .leica(StyleLibrary.default) }
}
