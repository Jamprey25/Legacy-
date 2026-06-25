import Foundation

/// Copy for the unlock ceremony — reinforces "the places remember you."
public enum UnlockReturnNarrative {
    public static func headline(returnCount: Int) -> String {
        switch returnCount {
        case 0, 1:
            return "First time back"
        case 2:
            return "You've returned twice"
        default:
            return "You've returned \(returnCount) times"
        }
    }

    public static func subtitle(returnCount: Int, dropDate: String?) -> String {
        if returnCount <= 1 {
            if let dropDate, !dropDate.isEmpty {
                return "Dropped \(dropDate) · this place remembers you"
            }
            return "This place remembers you"
        }
        return "The place remembers every return"
    }

    public static func firstDiscoveryToast() -> String {
        "First time here since you dropped this"
    }

    public static func lastUnlockedLabel(iso8601: String?) -> String? {
        guard let iso8601, !iso8601.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso8601)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso8601)
        }
        guard let date else { return nil }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return "Last unlocked \(display.string(from: date))"
    }
}
