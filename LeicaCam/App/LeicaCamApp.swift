import SwiftUI

@main
struct LeicaCamApp: App {
    var body: some Scene {
        WindowGroup {
            CameraView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
