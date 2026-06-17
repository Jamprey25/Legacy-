import APIClient
import CoreLocation
import DesignSystem
import LocationEngine
import SwiftUI

/// Wander mode: movement-gated scan loop, warmth cue, unlock flow.
/// Warmth cue is non-directional — screen-edge gradient only (DEC-15).
public enum WanderFeature {
    public static let version = "0.1.0"
}

@MainActor
@Observable
public final class WanderCoordinator {
    public init(
        apiClient: LegacyAPIClient,
        locationEngine: LocationEngine,
        haptics: WarmthHapticFeedback? = nil
    ) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
        self.haptics = haptics ?? WarmthHaptics.platformDefault
    }

    private let apiClient: LegacyAPIClient
    private let locationEngine: LocationEngine
    private let haptics: WarmthHapticFeedback
    private var previousWarmthLevel: WarmthLevel = .none

    /// Teasers from the latest scan — no coordinates (contract §4).
    public private(set) var teasers: [Teaser] = []
    public private(set) var isScanning = false
    public private(set) var isUnlocking = false
    public private(set) var statusMessage: String?
    public private(set) var unlockedMediaURL: URL?
    public private(set) var unlockedCaption: String?

    /// Ambient warmth intensity 0…1. No directional component.
    public var warmthIntensity: Double = 0

    public var isShowingUnlockedMedia: Bool { unlockedMediaURL != nil }

    public func dismissUnlockedMedia() {
        unlockedMediaURL = nil
        unlockedCaption = nil
    }

    /// Movement-gated foreground scan. Safe to call on appear and after significant movement.
    public func scanIfNeeded(force: Bool = false) async {
        guard !isScanning else { return }

        isScanning = true
        statusMessage = nil
        defer { isScanning = false }

        do {
            let fix = try await locationEngine.acquireFix()

            if !force, !locationEngine.shouldScan(for: fix) {
                return
            }

            let body = LocationRequest(lat: fix.lat, lng: fix.lng, accuracyM: fix.accuracyM)

            if let response = try await apiClient.scan(body) {
                teasers = response.teasers
            } else {
                teasers = []
            }

            applyWarmth(from: teasers)

            locationEngine.recordScan(
                at: CLLocation(latitude: fix.lat, longitude: fix.lng)
            )
        } catch {
            statusMessage = "Scan failed. Check location permission and connectivity."
        }
    }

    /// Attempt unlock for a teaser pin. Handles dwell-required UX messaging.
    public func unlock(teaser: Teaser) async {
        guard !isUnlocking else { return }

        isUnlocking = true
        statusMessage = nil
        unlockedMediaURL = nil
        unlockedCaption = nil
        defer { isUnlocking = false }

        do {
            let fix = try await locationEngine.acquireFix()
            let body = LocationRequest(lat: fix.lat, lng: fix.lng, accuracyM: fix.accuracyM)
            let response = try await apiClient.unlock(memoryID: teaser.memoryID, body)

            if let urlString = response.media.first?.url, let url = URL(string: urlString) {
                unlockedMediaURL = url
            }
            unlockedCaption = response.caption
            statusMessage = response.caption
        } catch let LegacyAPIError.locked(code, message, info) {
            switch code {
            case "dwell_required":
                statusMessage = message.isEmpty
                    ? "Stay here a moment longer."
                    : message
                if let seconds = info.retryAfterSeconds {
                    statusMessage? += " (~\(seconds)s)"
                }
            case "not_in_range":
                statusMessage = "Walk closer to open this memory."
            case "sealed", "condition_unmet":
                statusMessage = message
            default:
                statusMessage = message
            }
        } catch {
            statusMessage = "Could not unlock. Try again when you have a signal."
        }
    }

    private func applyWarmth(from teasers: [Teaser]) {
        let level = WanderScanPolicy.maxWarmthLevel(from: teasers)
        warmthIntensity = level.intensity
        if level != previousWarmthLevel {
            haptics.playTransition(to: level)
            previousWarmthLevel = level
        }
    }
}

public struct WanderFeatureRootView: View {
    public init(coordinator: WanderCoordinator) {
        self.coordinator = coordinator
    }

    @Bindable private var coordinator: WanderCoordinator

    public var body: some View {
        ZStack {
            LegacyColor.background
                .ignoresSafeArea()

            VStack(spacing: LegacySpacing.lg) {
                if coordinator.teasers.isEmpty {
                    ContentUnavailableView(
                        "Wander",
                        systemImage: "map",
                        description: Text("Walk to discover memories nearby.")
                    )
                } else {
                    List(coordinator.teasers, id: \.memoryID) { teaser in
                        TeaserRow(teaser: teaser) {
                            Task { await coordinator.unlock(teaser: teaser) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }

                if coordinator.isScanning || coordinator.isUnlocking {
                    ProgressView()
                        .tint(LegacyColor.accent)
                }

                if let message = coordinator.statusMessage, !coordinator.isShowingUnlockedMedia {
                    Text(message)
                        .font(LegacyFont.callout)
                        .foregroundStyle(LegacyColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, LegacySpacing.lg)
                }
            }

            WarmthCueOverlay(intensity: coordinator.warmthIntensity)
                .ignoresSafeArea()
        }
        .task {
            await coordinator.scanIfNeeded(force: true)
        }
        .sheet(isPresented: Binding(
            get: { coordinator.isShowingUnlockedMedia },
            set: { if !$0 { coordinator.dismissUnlockedMedia() } }
        )) {
            if let url = coordinator.unlockedMediaURL {
                UnlockedMemorySheet(url: url, caption: coordinator.unlockedCaption)
            }
        }
    }
}

private struct TeaserRow: View {
    let teaser: Teaser
    let onUnlock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LegacySpacing.xs) {
            Text(teaser.ownerDisplay == "you" ? "Your memory" : teaser.ownerDisplay)
                .font(LegacyFont.headline)
                .foregroundStyle(LegacyColor.textPrimary)
            Text(teaser.dropDate)
                .font(LegacyFont.caption)
                .foregroundStyle(LegacyColor.textSecondary)
            HStack {
                Text(teaser.inRange ? "In range" : "Nearby")
                    .font(LegacyFont.caption)
                    .foregroundStyle(teaser.inRange ? LegacyColor.accent : LegacyColor.textSecondary)
                Spacer()
                if teaser.inRange {
                    Button("Open", action: onUnlock)
                        .buttonStyle(.legacyPrimary)
                        .frame(maxWidth: 120)
                }
            }
        }
        .listRowBackground(LegacyColor.surface)
    }
}

private struct UnlockedMemorySheet: View {
    let url: URL
    let caption: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LegacySpacing.lg) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
                        case .failure:
                            ContentUnavailableView("Could not load", systemImage: "photo")
                        default:
                            ProgressView()
                                .tint(LegacyColor.accent)
                        }
                    }

                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(LegacyFont.body)
                            .foregroundStyle(LegacyColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(LegacySpacing.lg)
            }
            .background(LegacyColor.background)
            .navigationTitle("Memory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
