import SwiftUI

/// Main viewfinder screen.
struct CameraView: View {
    @StateObject private var camera = CameraService()

    var body: some View {
        ZStack {
            LeicaTheme.background.ignoresSafeArea()

            switch camera.state {
            case .denied:
                PermissionDeniedView()
            case .failed(let message):
                ErrorView(message: message)
            default:
                content
            }
        }
        .onAppear {
            HapticsManager.shared.prepare()
            camera.start()
        }
        .onDisappear { camera.stop() }
        .fullScreenCover(item: $camera.captured) { photo in
            ReviewView(
                processed: photo.image,
                original: photo.original,
                onSave: { image in camera.save(image: image) { _ in } },
                onDiscard: { camera.captured = nil }
            )
        }
    }

    // MARK: - Main layout

    private var content: some View {
        VStack(spacing: 0) {
            viewfinder
            readoutBar
            StylePickerView(styles: AppStyleLibrary.all,
                            selected: $camera.selectedStyle,
                            onSelect: { _ in HapticsManager.shared.selectionChanged() })
                .padding(.vertical, 10)
            bottomBar
        }
    }

    /// 3:2 viewfinder (portrait → height = width × 1.5), edge-to-edge.
    private var viewfinder: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = width * 1.5
            ZStack {
                CameraPreviewView(camera: camera)
                    .frame(width: width, height: height)
                    .clipped()

                ControlsOverlay(showGrid: camera.showGrid, focusPoint: camera.focusIndicator)
                    .frame(width: width, height: height)

                // Shutter flash.
                Color.white
                    .opacity(camera.flashOpacity)
                    .frame(width: width, height: height)
                    .animation(.easeOut(duration: 0.25), value: camera.flashOpacity)
                    .allowsHitTesting(false)
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }

    /// EV + ISO technical readout.
    private var readoutBar: some View {
        HStack(spacing: 18) {
            Text(String(format: "EV %+.1f", camera.exposureBias))
            Text(String(format: "ISO %.0f", camera.iso))
            Spacer()
            Button { camera.showGrid.toggle() } label: {
                Image(systemName: camera.showGrid ? "grid" : "grid")
                    .foregroundColor(camera.showGrid ? LeicaTheme.primaryText : LeicaTheme.dimText)
            }
        }
        .font(LeicaTheme.mono(13))
        .foregroundColor(LeicaTheme.secondaryText)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    /// Thumbnail · shutter · settings.
    private var bottomBar: some View {
        HStack {
            // Last capture thumbnail.
            Group {
                if let thumb = camera.lastThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(LeicaTheme.dimText, lineWidth: 1)
                        .frame(width: 46, height: 46)
                }
            }
            .frame(maxWidth: .infinity)

            ShutterButton { capture() }
                .frame(maxWidth: .infinity)

            Button {
                camera.saveOriginal.toggle()
                HapticsManager.shared.selectionChanged()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(camera.saveOriginal ? LeicaTheme.primaryText : LeicaTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 28)
    }

    private func capture() {
        HapticsManager.shared.shutter()
        camera.capturePhoto()
    }
}

// MARK: - Shutter button

private struct ShutterButton: View {
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(LeicaTheme.leicaRed, lineWidth: 2)
                .frame(width: 74, height: 74)
            Circle()
                .fill(LeicaTheme.primaryText)
                .frame(width: 62, height: 62)
        }
        .scaleEffect(pressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: pressed)
        .contentShape(Circle())
        .onTapGesture { action() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

// MARK: - State screens

private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.none")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundColor(LeicaTheme.secondaryText)
            Text("Camera Access Needed")
                .font(LeicaTheme.label(22))
                .foregroundColor(LeicaTheme.primaryText)
            Text("Enable camera access in Settings to use LeicaCam.")
                .font(LeicaTheme.mono(13))
                .foregroundColor(LeicaTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(LeicaTheme.label(17))
            .foregroundColor(LeicaTheme.leicaRed)
            .padding(.top, 6)
        }
        .padding(40)
    }
}

private struct ErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundColor(LeicaTheme.secondaryText)
            Text("Camera Unavailable")
                .font(LeicaTheme.label(22))
                .foregroundColor(LeicaTheme.primaryText)
            Text(message)
                .font(LeicaTheme.mono(12))
                .foregroundColor(LeicaTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
