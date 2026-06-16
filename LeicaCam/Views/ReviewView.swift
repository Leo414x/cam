import SwiftUI

/// Post-capture review. Shows the processed photo full-screen with discard /
/// save actions. Press and hold to peek at the unprocessed original.
struct ReviewView: View {
    let processed: UIImage
    let original: UIImage?
    let onSave: (UIImage) -> Void
    let onDiscard: () -> Void

    @State private var showingOriginal = false
    @State private var watermark = false
    @State private var saved = false

    private var displayImage: UIImage {
        if watermark, !showingOriginal {
            return WatermarkRenderer.apply(to: processed, lens: .wide)
        }
        return (showingOriginal ? original : nil) ?? processed
    }

    var body: some View {
        ZStack {
            LeicaTheme.background.ignoresSafeArea()

            Image(uiImage: displayImage)
                .resizable()
                .scaledToFit()
                .ignoresSafeArea(edges: .top)
                .gesture(
                    LongPressGesture(minimumDuration: 0.15)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { _ in if original != nil { showingOriginal = true } }
                        .onEnded { _ in showingOriginal = false }
                )

            if showingOriginal {
                VStack {
                    Text("ORIGINAL")
                        .font(LeicaTheme.mono(11))
                        .tracking(2)
                        .foregroundColor(LeicaTheme.primaryText.opacity(0.7))
                        .padding(.top, 60)
                    Spacer()
                }
            }

            VStack {
                // Watermark toggle, top-right.
                HStack {
                    Spacer()
                    Button { watermark.toggle() } label: {
                        Image(systemName: watermark ? "textformat.size.larger" : "textformat.size")
                            .font(.system(size: 17))
                            .foregroundColor(watermark ? LeicaTheme.primaryText : LeicaTheme.secondaryText)
                            .padding(12)
                    }
                }
                .padding(.top, 50)

                Spacer()

                if original != nil {
                    Text("HOLD TO COMPARE")
                        .font(LeicaTheme.mono(10))
                        .tracking(2)
                        .foregroundColor(LeicaTheme.dimText)
                        .padding(.bottom, 18)
                }

                HStack(spacing: 0) {
                    Button(action: discard) {
                        Label("Discard", systemImage: "xmark")
                            .font(LeicaTheme.label(18))
                            .foregroundColor(LeicaTheme.secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                    Button(action: save) {
                        Label(saved ? "Saved" : "Save",
                              systemImage: saved ? "checkmark" : "square.and.arrow.down")
                            .font(LeicaTheme.label(18))
                            .foregroundColor(saved ? LeicaTheme.leicaRed : LeicaTheme.primaryText)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(saved)
                }
                .padding(.vertical, 22)
                .background(LeicaTheme.background.opacity(0.6))
            }
        }
    }

    private func save() {
        let output = watermark ? WatermarkRenderer.apply(to: processed, lens: .wide) : processed
        onSave(output)
        HapticsManager.shared.success()
        withAnimation(.easeInOut(duration: 0.25)) { saved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDiscard() }
    }

    private func discard() {
        HapticsManager.shared.selectionChanged()
        onDiscard()
    }
}
