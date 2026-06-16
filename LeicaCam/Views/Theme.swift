import SwiftUI

/// Shared visual language: pure black, Leica red, restrained typography.
enum LeicaTheme {
    static let background = Color.black
    static let leicaRed = Color(red: 0xE6 / 255, green: 0x00 / 255, blue: 0x12 / 255)
    static let primaryText = Color.white
    static let secondaryText = Color(white: 0.53)   // ~#888
    static let dimText = Color(white: 0.40)          // ~#666

    /// SF Mono technical readouts (EV, ISO, focal length).
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// SF Pro Display ultralight for sparse labels.
    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .ultraLight, design: .default)
    }
}
