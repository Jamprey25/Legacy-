import Foundation

/// Shared App Group for widget ↔ main-app data (On this day teaser).
public enum LegacyAppGroup {
    public static let identifier = "group.app.legacy.shared"

    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
