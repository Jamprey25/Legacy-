import Foundation

/// Wire shapes for optional seal/condition on `POST /v1/memories` (contract §6).
public enum MemorySealPayload: Encodable, Sendable, Equatable {
    case fixedDate(openAt: String)
    case duration(lockedHours: Int)
    case ageBased(recipientDOB: String, openAtAge: Int)
    case recurring(windowStart: String, windowDurationHours: Int)

    enum CodingKeys: String, CodingKey {
        case type
        case openAt = "open_at"
        case lockedHours = "locked_hours"
        case recipientDOB = "recipient_dob"
        case openAtAge = "open_at_age"
        case windowStart = "window_start"
        case windowDurationHours = "window_duration_hours"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixedDate(let openAt):
            try container.encode("fixed_date", forKey: .type)
            try container.encode(openAt, forKey: .openAt)
        case .duration(let hours):
            try container.encode("duration", forKey: .type)
            try container.encode(hours, forKey: .lockedHours)
        case .ageBased(let dob, let age):
            try container.encode("age_based", forKey: .type)
            try container.encode(dob, forKey: .recipientDOB)
            try container.encode(age, forKey: .openAtAge)
        case .recurring(let start, let hours):
            try container.encode("recurring", forKey: .type)
            try container.encode(start, forKey: .windowStart)
            try container.encode(hours, forKey: .windowDurationHours)
        }
    }
}

public enum MemoryConditionPayload: Encodable, Sendable, Equatable {
    case timeOfDay(afterHour: Int, beforeHour: Int, timeFallback: String)
    case season(monthStart: Int, monthEnd: Int, timeFallback: String)
    case longAbsence(daysSinceLastFind: Int, timeFallback: String)
    case nthReturn(n: Int, timeFallback: String)

    enum CodingKeys: String, CodingKey {
        case type
        case afterHour = "after_hour"
        case beforeHour = "before_hour"
        case monthStart = "month_start"
        case monthEnd = "month_end"
        case daysSinceLastFind = "days_since_last_find"
        case n
        case timeFallback = "time_fallback"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .timeOfDay(let after, let before, let fallback):
            try container.encode("time_of_day", forKey: .type)
            try container.encode(after, forKey: .afterHour)
            try container.encode(before, forKey: .beforeHour)
            try container.encode(fallback, forKey: .timeFallback)
        case .season(let start, let end, let fallback):
            try container.encode("season", forKey: .type)
            try container.encode(start, forKey: .monthStart)
            try container.encode(end, forKey: .monthEnd)
            try container.encode(fallback, forKey: .timeFallback)
        case .longAbsence(let days, let fallback):
            try container.encode("long_absence", forKey: .type)
            try container.encode(days, forKey: .daysSinceLastFind)
            try container.encode(fallback, forKey: .timeFallback)
        case .nthReturn(let n, let fallback):
            try container.encode("nth_return", forKey: .type)
            try container.encode(n, forKey: .n)
            try container.encode(fallback, forKey: .timeFallback)
        }
    }
}
