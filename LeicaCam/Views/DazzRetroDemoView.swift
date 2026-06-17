import SwiftUI
import UIKit

/// Verification screen: applies all 8 Polaroid presets to one bundled sample
/// image. The toggle switches between the full effect (LUT + style + textures)
/// and LUT-only, so the layers can be A/B compared.
struct DazzRetroDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var fullEffect = true
    @State private var rendered: [String: UIImage] = [:]

    private let sample = DazzRetroDemoView.loadSample()
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Toggle("Full effect (off = LUT only)", isOn: $fullEffect)
                    .padding(.horizontal).padding(.vertical, 10)

                ScrollView {
                    if let sample {
                        // Original reference first.
                        thumb(title: "Original", image: sample)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 6)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(DazzRetroLibrary.all) { preset in
                                thumb(title: "\(preset.code) · \(preset.name)",
                                      image: rendered[preset.id])
                            }
                        }
                        .padding(.horizontal)
                    } else {
                        Text("Sample image not found in bundle.")
                            .foregroundColor(.secondary).padding()
                    }
                }
            }
            .navigationTitle("Polaroid demo")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: renderAll)
        .onChange(of: fullEffect) { _ in renderAll() }
    }

    @ViewBuilder
    private func thumb(title: String, image: UIImage?) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Color.black.opacity(0.05)
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(title).font(.caption).foregroundColor(.secondary)
        }
    }

    private func renderAll() {
        guard let sample else { return }
        let full = fullEffect
        DispatchQueue.global(qos: .userInitiated).async {
            var out: [String: UIImage] = [:]
            for preset in DazzRetroLibrary.all {
                if let img = DazzRetroProcessor.shared.processSample(
                    sample, preset: preset, applyStyle: full, applyTextures: full) {
                    out[preset.id] = img
                }
            }
            DispatchQueue.main.async { rendered = out }
        }
    }

    private static func loadSample() -> UIImage? {
        guard let url = Bundle.main.url(forResource: "sample_polaroid_origin", withExtension: "jpg") else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}
