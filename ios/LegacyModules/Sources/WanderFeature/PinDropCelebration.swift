import DesignSystem
import Foundation
import LocationEngine
import SwiftUI

/// Post-drop/import celebration: progress copy + staggered pin reveal on Wander (~80ms).
@MainActor
@Observable
public final class PinDropCelebrationCoordinator {
    public init() {}

    public enum Phase: Equatable {
        case idle
        case loading(message: String, progress: Double)
        case revealing(revealedIDs: Set<String>, total: Int)
    }

    private static let loadingMessages = [
        "Loading your memories…",
        "Creating your legacy…",
        "Placing your pins…",
    ]

    public private(set) var phase: Phase = .idle
    public private(set) var pins: [CachedOwnPin] = []

    public var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    /// IDs currently visible on the Wander map (`nil` = show all cached own pins).
    public var mapVisiblePinIDs: Set<String>? {
        switch phase {
        case .idle:
            return nil
        case .loading:
            return []
        case .revealing(let revealedIDs, _):
            return revealedIDs
        }
    }

    public var overlayMessage: String? {
        switch phase {
        case .idle:
            return nil
        case .loading(let message, _):
            return message
        case .revealing(let revealed, let total):
            return revealed.count >= total ? "Your map is coming alive" : "Dropping pins…"
        }
    }

    public var overlayProgress: Double? {
        switch phase {
        case .idle:
            return nil
        case .loading(_, let progress):
            return progress
        case .revealing(let revealed, let total):
            guard total > 0 else { return 1 }
            return 0.55 + (Double(revealed.count) / Double(total)) * 0.45
        }
    }

    /// Persists pins, reloads Wander cache, runs loading + stagger reveal.
    public func celebrate(pins newPins: [CachedOwnPin], wander: WanderCoordinator) async {
        guard !newPins.isEmpty else { return }

        pins = newPins
        for pin in newPins {
            OwnMemoryPinCache.save(pin)
        }
        wander.reloadOwnPins()
        wander.setMapPinFilter([])

        for (index, message) in Self.loadingMessages.enumerated() {
            let progress = Double(index + 1) / Double(Self.loadingMessages.count + 1) * 0.5
            phase = .loading(message: message, progress: progress)
            try? await Task.sleep(for: .milliseconds(750))
        }

        var revealed = Set<String>()
        phase = .revealing(revealedIDs: revealed, total: newPins.count)

        for pin in newPins {
            revealed.insert(pin.memoryID)
            wander.setMapPinFilter(revealed)
            phase = .revealing(revealedIDs: revealed, total: newPins.count)
            try? await Task.sleep(for: .milliseconds(80))
        }

        try? await Task.sleep(for: .milliseconds(900))
        wander.setMapPinFilter(nil)
        phase = .idle
        pins = []
    }

    public func cancel() {
        phase = .idle
        pins = []
    }
}

struct PinDropCelebrationOverlay: View {
    let message: String
    let progress: Double

    var body: some View {
        VStack(spacing: LegacySpacing.sm) {
            ProgressView(value: progress)
                .tint(LegacyColor.accent)
            Text(message)
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(LegacySpacing.lg)
        .frame(maxWidth: .infinity)
        .background(LegacyColor.surface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(.horizontal, LegacySpacing.xl)
        .padding(.bottom, LegacySpacing.xl)
    }
}
