import SwiftUI

/// Debug edit panel for the selected Polaroid preset. Sliders mutate the preset
/// embedded in `camera.selectedStyle`, so the live preview updates as you drag.
/// Set texture/style values to 0 (or LUT intensity to compare) for A/B testing.
struct DazzRetroEditPanel: View {
    @ObservedObject var camera: CameraService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if let preset = camera.selectedPolaroid {
                    Form {
                        Section("LUT") {
                            slider("LUT intensity", \.lutIntensity, 0, 1)
                        }
                        Section("Style") {
                            slider("Brightness", \.style.brightness, -1, 1)
                            slider("Contrast", \.style.contrast, 0, 4)
                            slider("Saturation", \.style.saturation, 0, 5)
                            slider("Sharpen", \.style.sharpen, 0, 10)
                            slider("Exposure", \.style.exposure, -1, 1)
                            slider("Temperature", \.style.whiteBalanceTemperature, -1, 1)
                            slider("Tint", \.style.whiteBalanceTint, 0, 5)
                        }
                        Section("Texture / Filter") {
                            slider("Vignette", \.style.vignette, 0, 1)
                            slider("Grain", \.style.grain, 0, 1)
                            slider("Dust", \.textures.dustIntensity, 0, 1)
                            slider("Light leak", \.textures.lightLeakIntensity, 0, 1)
                        }
                        Section {
                            Button("Reset to preset defaults", role: .destructive) {
                                if let fresh = DazzRetroLibrary.defaults(forID: preset.id) {
                                    camera.selectedPolaroid = fresh
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableViewCompat(
                        title: "No Polaroid style selected",
                        message: "Pick a PO1–PO8 style to edit its parameters.")
                }
            }
            .navigationTitle(camera.selectedPolaroid?.name ?? "Polaroid")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Slider helper

    @ViewBuilder
    private func slider(_ label: String,
                        _ keyPath: WritableKeyPath<DazzRetroPolaroidPreset, Float>,
                        _ lo: Float, _ hi: Float) -> some View {
        let binding = Binding<Float>(
            get: { camera.selectedPolaroid?[keyPath: keyPath] ?? lo },
            set: { newValue in
                if var p = camera.selectedPolaroid {
                    p[keyPath: keyPath] = newValue
                    camera.selectedPolaroid = p
                }
            })
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", binding.wrappedValue))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: binding, in: lo...hi)
        }
    }
}

/// Minimal stand-in for `ContentUnavailableView` (keeps the iOS 17 deployment
/// target without an availability split).
private struct ContentUnavailableViewCompat: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.largeTitle).foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
