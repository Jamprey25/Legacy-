import Foundation

/// Tracks whether we've shown the pre-TestFlight Always-permission education sheet.
public enum BackgroundLocationPermissionGate {
    private static let dismissedKey = "legacy.backgroundDiscoveryPromptDismissed"

    public static var hasUserDismissedPrompt: Bool {
        UserDefaults.standard.bool(forKey: dismissedKey)
    }

    public static func markPromptDismissed() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    #if DEBUG
    public static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: dismissedKey)
    }
    #endif
}
