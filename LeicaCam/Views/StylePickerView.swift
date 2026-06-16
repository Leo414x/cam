import SwiftUI

/// Horizontal carousel of style pills below the viewfinder. Selecting a style
/// updates the live preview in real time.
struct StylePickerView: View {
    let styles: [LeicaStyle]
    @Binding var selected: LeicaStyle
    var onSelect: (LeicaStyle) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 26) {
                ForEach(styles) { style in
                    pill(for: style)
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 38)
    }

    @ViewBuilder
    private func pill(for style: LeicaStyle) -> some View {
        let isSelected = style == selected
        VStack(spacing: 6) {
            Text(style.displayName)
                .font(LeicaTheme.label(15))
                .tracking(0.5)
                .foregroundColor(isSelected ? LeicaTheme.primaryText : LeicaTheme.dimText)
            Rectangle()
                .fill(isSelected ? LeicaTheme.primaryText : Color.clear)
                .frame(width: 22, height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isSelected else { return }
            withAnimation(.easeInOut(duration: 0.2)) { selected = style }
            onSelect(style)
        }
    }
}
