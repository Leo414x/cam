import UIKit

/// Centralized haptic feedback. Generators are pre-prepared so the shutter
/// feels instantaneous.
final class HapticsManager {
    static let shared = HapticsManager()

    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {}

    func prepare() {
        impact.prepare()
        notification.prepare()
        selection.prepare()
    }

    /// Shutter press.
    func shutter() {
        impact.impactOccurred()
        impact.prepare()
    }

    /// Photo saved.
    func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    /// Style pill changed.
    func selectionChanged() {
        selection.selectionChanged()
        selection.prepare()
    }
}
