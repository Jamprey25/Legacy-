import Foundation

/// Client-side draft for V2 Treasure Chest / V4 Note in a Bottle compose flows.
/// Seals and conditions are evaluated server-side at unlock only (contract §6).
public struct DropComposeDraft: Sendable, Equatable {
    public var teaserText: String
    public var privacyTier: PrivacyTierDraft
    public var seal: SealDraft
    public var condition: ConditionDraft?
    public var noteText: String
    /// E.164 or US-local phone numbers to summon after drop (Phase 2 preview).
    public var recipientPhones: [String]

    public init(
        teaserText: String = "",
        privacyTier: PrivacyTierDraft = .private,
        seal: SealDraft = .none,
        condition: ConditionDraft? = nil,
        noteText: String = "",
        recipientPhones: [String] = []
    ) {
        self.teaserText = teaserText
        self.privacyTier = privacyTier
        self.seal = seal
        self.condition = condition
        self.noteText = noteText
        self.recipientPhones = recipientPhones
    }

    public static let pinDefault = DropComposeDraft()
}

public enum PrivacyTierDraft: String, Sendable, CaseIterable, Identifiable {
    case `private`
    case recipients
    case friends

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .private: return "Private"
        case .recipients: return "Recipients"
        case .friends: return "Friends"
        }
    }

    /// Phase 1 API accepts private only; others are UI placeholders until M6.
    public var isAvailableInPhase1: Bool {
        self == .private
    }
}

public enum SealDraft: Sendable, Equatable {
    case none
    case fixedDate(Date)
    case duration(hours: Int)
    case ageBased(recipientDOB: Date, openAtAge: Int)
    case recurring(windowStartMMDD: String, durationHours: Int)

    public var label: String {
        switch self {
        case .none: return "Open now"
        case .fixedDate: return "Open on date"
        case .duration: return "Time lock"
        case .ageBased: return "Age milestone"
        case .recurring: return "Seasonal window"
        }
    }

    /// Seal types surfaced in the V4 Note in a Bottle picker (time-only).
    public static let noteBottleSealLabels: [(SealDraft, String)] = [
        (.none, "Open now"),
        (.duration(hours: 24), "24-hour lock"),
        (.duration(hours: 168), "1-week lock"),
    ]
}

public enum ConditionDraft: Sendable, Equatable {
    case timeOfDay(afterHour: Int, beforeHour: Int, fallback: Date)
    case season(monthStart: Int, monthEnd: Int, fallback: Date)
    case longAbsence(days: Int, fallback: Date)
    case nthReturn(n: Int, fallback: Date)

    public var label: String {
        switch self {
        case .timeOfDay: return "Time of day"
        case .season: return "Season"
        case .longAbsence: return "Long absence"
        case .nthReturn: return "Nth return"
        }
    }

    public var fallbackDate: Date {
        switch self {
        case .timeOfDay(_, _, let fallback),
             .season(_, _, let fallback),
             .longAbsence(_, let fallback),
             .nthReturn(_, let fallback):
            return fallback
        }
    }
}
