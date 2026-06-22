#if os(iOS)
import UIKit
#endif

/// Discrete UI feedback for success/failure moments (drop, unlock, import).
/// Distinct from `WarmthHaptics`, which encodes continuous proximity warmth.
@MainActor
public enum LegacyHaptics {
    /// Confirms a completed action (memory dropped, unlocked, imported).
    public static func success() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    /// Signals a recoverable problem (action failed, validation issue).
    public static func warning() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        #endif
    }

    /// Light tick for discrete selection changes (toggles, segment picks).
    public static func selection() {
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
