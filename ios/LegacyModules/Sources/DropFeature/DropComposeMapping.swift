import APIClient
import Foundation

enum DropComposeMapping {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()

    static func sealPayload(from draft: SealDraft) -> MemorySealPayload? {
        switch draft {
        case .none:
            return nil
        case .fixedDate(let date):
            return .fixedDate(openAt: iso8601.string(from: date))
        case .duration(let hours):
            return .duration(lockedHours: hours)
        case .ageBased(let dob, let age):
            return .ageBased(recipientDOB: dayFormatter.string(from: dob), openAtAge: age)
        case .recurring(let start, let hours):
            return .recurring(windowStart: start, windowDurationHours: hours)
        }
    }

    static func conditionPayload(from draft: ConditionDraft) -> MemoryConditionPayload {
        switch draft {
        case .timeOfDay(let after, let before, let fallback):
            return .timeOfDay(
                afterHour: after,
                beforeHour: before,
                timeFallback: iso8601.string(from: fallback)
            )
        case .season(let start, let end, let fallback):
            return .season(
                monthStart: start,
                monthEnd: end,
                timeFallback: iso8601.string(from: fallback)
            )
        case .longAbsence(let days, let fallback):
            return .longAbsence(
                daysSinceLastFind: days,
                timeFallback: iso8601.string(from: fallback)
            )
        case .nthReturn(let n, let fallback):
            return .nthReturn(n: n, timeFallback: iso8601.string(from: fallback))
        }
    }
}
