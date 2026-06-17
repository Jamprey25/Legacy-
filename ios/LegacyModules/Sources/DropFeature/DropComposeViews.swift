import DesignSystem
import SwiftUI

#if os(iOS)
import UIKit
#endif

public enum DropTabMode: String, CaseIterable, Identifiable, Sendable {
    case pin
    case treasure
    case note

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .pin: return "Quick pin"
        case .treasure: return "Treasure"
        case .note: return "Note"
        }
    }

    public var icon: String {
        switch self {
        case .pin: return "mappin.and.ellipse"
        case .treasure: return "shippingbox"
        case .note: return "text.bubble"
        }
    }
}

struct DropComposeViews {
    struct TreasureChestForm: View {
        @Binding var compose: DropComposeDraft
        let hasPhoto: Bool
        let isDropping: Bool
        let onDrop: () -> Void

        var body: some View {
            Form {
                Section("Photo") {
                    if hasPhoto {
                        Text("Photo selected")
                            .foregroundStyle(LegacyColor.textSecondary)
                        Text("Use Quick pin mode to change the photo, or drop from here.")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    } else {
                        Text("Select a photo under Quick pin first, then return here to compose.")
                            .foregroundStyle(LegacyColor.danger)
                    }
                }

                Section("Teaser") {
                    TextField("Hint shown before unlock", text: $compose.teaserText, axis: .vertical)
                        .lineLimit(2...4)
                }

                SealPickerSection(seal: $compose.seal)

                ConditionPickerSection(condition: $compose.condition)

                PrivacyPickerSection(tier: $compose.privacyTier)

                Section("Recipients") {
                    Text("Recipient targeting ships in a future update.")
                        .font(LegacyFont.caption)
                        .foregroundStyle(LegacyColor.textSecondary)
                }

                Section {
                    Button("Drop treasure chest", action: onDrop)
                        .disabled(!hasPhoto || isDropping)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LegacyColor.background)
        }
    }

    struct NoteBottleForm: View {
        @Binding var compose: DropComposeDraft
        let isDropping: Bool
        let onDrop: () -> Void

        @State private var sealKind: NoteSealKind = .none
        @State private var fixedDate = Date().addingTimeInterval(86_400)

        enum NoteSealKind: String, CaseIterable, Identifiable {
            case none, hours24, hours168, fixedDate
            var id: String { rawValue }
            var label: String {
                switch self {
                case .none: return "Open now"
                case .hours24: return "24-hour lock"
                case .hours168: return "1-week lock"
                case .fixedDate: return "Open on date"
                }
            }
        }

        var body: some View {
            Form {
                Section("Your note") {
                    TextField("Write your message…", text: $compose.noteText, axis: .vertical)
                        .lineLimit(4...12)
                }

                Section("Time seal") {
                    Picker("Seal", selection: $sealKind) {
                        ForEach(NoteSealKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .onChange(of: sealKind) { _, _ in syncSeal() }

                    if sealKind == .fixedDate {
                        DatePicker("Opens", selection: $fixedDate, displayedComponents: [.date, .hourAndMinute])
                            .onChange(of: fixedDate) { _, _ in syncSeal() }
                    }
                }

                Section {
                    Text("Location is set from your current GPS fix when you drop.")
                        .font(LegacyFont.caption)
                        .foregroundStyle(LegacyColor.textSecondary)
                }

                Section {
                    Button("Send note in a bottle", action: onDrop)
                        .disabled(compose.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDropping)
                }
            }
            .scrollContentBackground(.hidden)
            .background(LegacyColor.background)
            .onAppear { loadSeal() }
        }

        private func loadSeal() {
            switch compose.seal {
            case .none: sealKind = .none
            case .duration(hours: 24): sealKind = .hours24
            case .duration(hours: 168): sealKind = .hours168
            case .fixedDate(let date): sealKind = .fixedDate; fixedDate = date
            default: sealKind = .none
            }
        }

        private func syncSeal() {
            switch sealKind {
            case .none: compose.seal = .none
            case .hours24: compose.seal = .duration(hours: 24)
            case .hours168: compose.seal = .duration(hours: 168)
            case .fixedDate: compose.seal = .fixedDate(fixedDate)
            }
        }
    }
}

private struct SealPickerSection: View {
    @Binding var seal: SealDraft

    @State private var sealKind: SealKind = .none
    @State private var fixedDate = Date().addingTimeInterval(86_400 * 30)
    @State private var durationHours = 24
    @State private var recipientDOB = Calendar.current.date(byAdding: .year, value: -10, to: Date()) ?? Date()
    @State private var openAtAge = 18
    @State private var windowStart = "06-01"
    @State private var windowHours = 168

    enum SealKind: String, CaseIterable, Identifiable {
        case none, fixedDate, duration, ageBased, recurring
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "Open now"
            case .fixedDate: return "Fixed date"
            case .duration: return "Duration lock"
            case .ageBased: return "Age milestone"
            case .recurring: return "Seasonal"
            }
        }
    }

    var body: some View {
        Section("Seal") {
            Picker("Type", selection: $sealKind) {
                ForEach(SealKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .onChange(of: sealKind) { _, _ in syncSeal() }

            switch sealKind {
            case .none:
                EmptyView()
            case .fixedDate:
                DatePicker("Opens", selection: $fixedDate, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: fixedDate) { _, _ in syncSeal() }
            case .duration:
                Stepper("Lock \(durationHours) hours", value: $durationHours, in: 1...8760, step: 1)
                    .onChange(of: durationHours) { _, _ in syncSeal() }
            case .ageBased:
                DatePicker("Recipient DOB", selection: $recipientDOB, displayedComponents: .date)
                    .onChange(of: recipientDOB) { _, _ in syncSeal() }
                Stepper("Opens at age \(openAtAge)", value: $openAtAge, in: 1...100)
                    .onChange(of: openAtAge) { _, _ in syncSeal() }
            case .recurring:
                TextField("Window start (MM-DD)", text: $windowStart)
                    .onChange(of: windowStart) { _, _ in syncSeal() }
                Stepper("Window \(windowHours) hours", value: $windowHours, in: 1...720)
                    .onChange(of: windowHours) { _, _ in syncSeal() }
            }
        }
        .onAppear { loadFromSeal() }
    }

    private func loadFromSeal() {
        switch seal {
        case .none: sealKind = .none
        case .fixedDate(let date): sealKind = .fixedDate; fixedDate = date
        case .duration(let hours): sealKind = .duration; durationHours = hours
        case .ageBased(let dob, let age): sealKind = .ageBased; recipientDOB = dob; openAtAge = age
        case .recurring(let start, let hours): sealKind = .recurring; windowStart = start; windowHours = hours
        }
    }

    private func syncSeal() {
        switch sealKind {
        case .none: seal = .none
        case .fixedDate: seal = .fixedDate(fixedDate)
        case .duration: seal = .duration(hours: durationHours)
        case .ageBased: seal = .ageBased(recipientDOB: recipientDOB, openAtAge: openAtAge)
        case .recurring: seal = .recurring(windowStartMMDD: windowStart, durationHours: windowHours)
        }
    }
}

private struct ConditionPickerSection: View {
    @Binding var condition: ConditionDraft?

    @State private var enabled = false
    @State private var kind: ConditionKind = .timeOfDay
    @State private var afterHour = 18
    @State private var beforeHour = 22
    @State private var monthStart = 12
    @State private var monthEnd = 2
    @State private var absenceDays = 365
    @State private var nthReturn = 3
    @State private var fallback = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()

    enum ConditionKind: String, CaseIterable, Identifiable {
        case timeOfDay, season, longAbsence, nthReturn
        var id: String { rawValue }
        var label: String {
            switch self {
            case .timeOfDay: return "Time of day"
            case .season: return "Season"
            case .longAbsence: return "Long absence"
            case .nthReturn: return "Nth return"
            }
        }
    }

    var body: some View {
        Section("Condition (optional)") {
            Toggle("Add unlock condition", isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    if on { syncCondition() } else { condition = nil }
                }

            if enabled {
                Picker("Type", selection: $kind) {
                    ForEach(ConditionKind.allCases) { entry in
                        Text(entry.label).tag(entry)
                    }
                }
                .onChange(of: kind) { _, _ in syncCondition() }

                switch kind {
                case .timeOfDay:
                    Stepper("After hour \(afterHour)", value: $afterHour, in: 0...23)
                        .onChange(of: afterHour) { _, _ in syncCondition() }
                    Stepper("Before hour \(beforeHour)", value: $beforeHour, in: 0...23)
                        .onChange(of: beforeHour) { _, _ in syncCondition() }
                case .season:
                    Stepper("Month start \(monthStart)", value: $monthStart, in: 1...12)
                        .onChange(of: monthStart) { _, _ in syncCondition() }
                    Stepper("Month end \(monthEnd)", value: $monthEnd, in: 1...12)
                        .onChange(of: monthEnd) { _, _ in syncCondition() }
                case .longAbsence:
                    Stepper("\(absenceDays) days away", value: $absenceDays, in: 1...3650)
                        .onChange(of: absenceDays) { _, _ in syncCondition() }
                case .nthReturn:
                    Stepper("Opens on visit #\(nthReturn)", value: $nthReturn, in: 1...50)
                        .onChange(of: nthReturn) { _, _ in syncCondition() }
                }

                DatePicker("Fallback opens", selection: $fallback, displayedComponents: [.date, .hourAndMinute])
                    .onChange(of: fallback) { _, _ in syncCondition() }

                Text("If the condition is never met, the memory opens on the fallback date.")
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
            }
        }
        .onAppear {
            enabled = condition != nil
            if let condition { load(from: condition) }
        }
    }

    private func load(from draft: ConditionDraft) {
        switch draft {
        case .timeOfDay(let after, let before, let fb):
            kind = .timeOfDay; afterHour = after; beforeHour = before; fallback = fb
        case .season(let start, let end, let fb):
            kind = .season; monthStart = start; monthEnd = end; fallback = fb
        case .longAbsence(let days, let fb):
            kind = .longAbsence; absenceDays = days; fallback = fb
        case .nthReturn(let n, let fb):
            kind = .nthReturn; nthReturn = n; fallback = fb
        }
    }

    private func syncCondition() {
        guard enabled else { condition = nil; return }
        switch kind {
        case .timeOfDay:
            condition = .timeOfDay(afterHour: afterHour, beforeHour: beforeHour, fallback: fallback)
        case .season:
            condition = .season(monthStart: monthStart, monthEnd: monthEnd, fallback: fallback)
        case .longAbsence:
            condition = .longAbsence(days: absenceDays, fallback: fallback)
        case .nthReturn:
            condition = .nthReturn(n: nthReturn, fallback: fallback)
        }
    }
}

private struct PrivacyPickerSection: View {
    @Binding var tier: PrivacyTierDraft

    var body: some View {
        Section("Privacy") {
            Picker("Who can find this", selection: $tier) {
                ForEach(PrivacyTierDraft.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.inline)

            if tier != .private {
                Text("Only Private is available in Phase 1. Your selection will drop as private until recipients/friends ship.")
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
            }
        }
    }
}
