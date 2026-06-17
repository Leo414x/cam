import SwiftUI

/// Horizontal carousel of style pills below the viewfinder. Selecting a style
/// updates the live preview in real time. Dazz LUT styles are grouped after the
/// Leica styles, separated by a thin divider.
struct StylePickerView: View {
    let styles: [AppStyle]
    @Binding var selected: AppStyle
    var onSelect: (AppStyle) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 26) {
                ForEach(Array(styles.enumerated()), id: \.element.id) { index, style in
                    // Divider whenever the section (Leica / Dazz / Polaroid) changes.
                    if index > 0, styles[index - 1].groupKey != style.groupKey {
                        Rectangle()
                            .fill(LeicaTheme.dimText.opacity(0.4))
                            .frame(width: 1, height: 20)
                    }
                    pill(for: style)
                }
            }
            .padding(.horizontal, 28)
        }
        .frame(height: 38)
    }

    @ViewBuilder
    private func pill(for style: AppStyle) -> some View {
        let isSelected = style == selected
        VStack(spacing: 6) {
            Text(style.name)
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
