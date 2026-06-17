import Foundation

enum MemoryLaneFormatting {
    /// Human-readable delta from drop date to now (e.g. "3 years ago").
    static func timeSinceDrop(createdAtISO: String, now: Date = Date()) -> String {
        guard let created = ISO8601DateFormatter().date(from: createdAtISO)
            ?? parseDateOnly(createdAtISO) else {
            return createdAtISO
        }

        let seconds = now.timeIntervalSince(created)
        if seconds < 0 { return "just dropped" }

        let days = Int(seconds / 86_400)
        if days == 0 { return "today" }
        if days == 1 { return "1 day ago" }
        if days < 30 { return "\(days) days ago" }

        let months = days / 30
        if months < 12 { return months == 1 ? "1 month ago" : "\(months) months ago" }

        let years = months / 12
        return years == 1 ? "1 year ago" : "\(years) years ago"
    }

    private static func parseDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
