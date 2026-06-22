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

    /// Parses a "yyyy-MM-dd" (or ISO8601) drop date into a `Date`.
    static func parseDay(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value) ?? parseDateOnly(value)
    }

    /// Calendar year for a drop date, or `nil` if unparseable.
    static func year(of dropDate: String, calendar: Calendar = .current) -> Int? {
        guard let date = parseDay(dropDate) else { return nil }
        return calendar.component(.year, from: date)
    }

    /// True when `dropDate` falls on today's month+day in a *previous* year ("on this day").
    static func isOnThisDay(dropDate: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let date = parseDay(dropDate) else { return false }
        let drop = calendar.dateComponents([.month, .day, .year], from: date)
        let today = calendar.dateComponents([.month, .day, .year], from: now)
        guard let dMonth = drop.month, let dDay = drop.day, let dYear = drop.year,
              let tMonth = today.month, let tDay = today.day, let tYear = today.year else {
            return false
        }
        return dMonth == tMonth && dDay == tDay && dYear < tYear
    }

    /// "1 year ago today" / "3 years ago today" for the on-this-day banner.
    static func yearsAgoToday(dropDate: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date = parseDay(dropDate) else { return "" }
        let years = max(1, calendar.component(.year, from: now) - calendar.component(.year, from: date))
        return years == 1 ? "1 year ago today" : "\(years) years ago today"
    }

    private static func parseDateOnly(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
