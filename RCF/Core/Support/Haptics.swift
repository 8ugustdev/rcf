import UIKit

/// Light haptic feedback helpers (tab switches, pulls, destructive taps).
enum Haptics {
    /// Subtle tick — selection changes, toggles.
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Success notification — completed operations.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning notification — throttled/degraded states.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Error notification — failed operations.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
