import SwiftUI

/// Overlays drawn on top of the live viewfinder: optional rule-of-thirds grid
/// and the tap-to-focus indicator.
struct ControlsOverlay: View {
    let showGrid: Bool
    let focusPoint: CGPoint?   // normalized 0...1 in the viewfinder's space

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showGrid {
                    GridLines()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                }

                if let focusPoint {
                    FocusSquare()
                        .position(x: focusPoint.x * geo.size.width,
                                  y: focusPoint.y * geo.size.height)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: focusPoint == nil)
        }
        .allowsHitTesting(false)
    }
}

/// Rule-of-thirds grid.
private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1..<3 {
            let x = rect.width * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            let y = rect.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}

/// Yellow focus reticle.
private struct FocusSquare: View {
    @State private var scale: CGFloat = 1.25
    var body: some View {
        Rectangle()
            .stroke(Color.yellow, lineWidth: 1.0)
            .frame(width: 72, height: 72)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { scale = 1.0 }
            }
    }
}
