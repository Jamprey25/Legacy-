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

    /// Unlock ceremony — stronger bloom on first return, lighter tick on revisits.
    public static func unlockCeremony(isFirstReturn: Bool) {
        #if os(iOS)
        if isFirstReturn {
            success()
        } else {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred(intensity: 0.65)
        }
        #endif
    }
}
