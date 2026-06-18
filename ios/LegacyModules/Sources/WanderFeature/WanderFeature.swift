import APIClient
import CoreLocation
import DesignSystem
import LocationEngine
import SwiftUI

#if os(iOS)
import MapKit
#endif

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
        networkMonitor: NetworkMonitor,
        haptics: WarmthHapticFeedback? = nil
    ) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
        self.networkMonitor = networkMonitor
        self.haptics = haptics ?? WarmthHaptics.platformDefault
        self.cachedOwnPins = OwnMemoryPinCache.load()
        self.teasers = WanderScanCache.load()
        if !teasers.isEmpty {
            applyWarmth(from: teasers)
        }
    }

    private let apiClient: LegacyAPIClient
    private let locationEngine: LocationEngine
    private let networkMonitor: NetworkMonitor
    private let haptics: WarmthHapticFeedback
    private var previousWarmthLevel: WarmthLevel = .none

    /// Teasers from the latest scan — no coordinates (contract §4).
    public private(set) var teasers: [Teaser] = []
    public private(set) var isScanning = false
    public private(set) var isUnlocking = false
    public private(set) var statusMessage: String?
    public private(set) var unlockedMediaURL: URL?
    public private(set) var unlockedCaption: String?

    /// Own-memory pins unlocked in range — safe to render offline (never stores others' coords).
    public private(set) var cachedOwnPins: [CachedOwnPin]

    /// Ambient warmth intensity 0…1. No directional component.
    public var warmthIntensity: Double = 0

    /// Latest user fix for map display only — never used to infer teaser direction.
    public private(set) var userCoordinate: CLLocationCoordinate2D?

    public var isOffline: Bool { networkMonitor.isOffline }

    /// True when offline but still in a coarse-or-closer warmth band (DEC-29).
    public var showsOfflineNearUX: Bool {
        isOffline && WanderScanPolicy.maxWarmthLevel(from: teasers) != .none
    }

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
            // Ensure we have authorization before requesting a fix. If undetermined,
            // prompt and let the delegate update; the user re-triggers scan on grant.
            if locationEngine.authorizationStatus == .notDetermined {
                locationEngine.requestWhenInUseAuthorization()
                statusMessage = "Waiting for location permission…"
                return
            }

            let fix = try await locationEngine.acquireFix()
            userCoordinate = CLLocationCoordinate2D(latitude: fix.lat, longitude: fix.lng)

            if !force, !locationEngine.shouldScan(for: fix) {
                return
            }

            let body = LocationRequest(lat: fix.lat, lng: fix.lng, accuracyM: fix.accuracyM)

            if let response = try await apiClient.scan(body) {
                teasers = response.teasers
                WanderScanCache.save(teasers: response.teasers)
            } else {
                teasers = []
                WanderScanCache.clear()
            }

            applyWarmth(from: teasers)

            locationEngine.recordScan(
                at: CLLocation(latitude: fix.lat, longitude: fix.lng)
            )
        } catch LocationEngineError.unauthorized {
            statusMessage = "Location access is off. Enable it in Settings to wander."
        } catch LocationEngineError.fixUnavailable {
            statusMessage = "Couldn't get your location. In Simulator: Features → Location → set one."
        } catch let error as LocationEngineError {
            statusMessage = "Location error: \(error)."
        } catch let error as LegacyAPIError where error.isConnectivityFailure {
            if teasers.isEmpty {
                teasers = WanderScanCache.load()
            }
            applyWarmth(from: teasers)
            statusMessage = showsOfflineNearUX
                ? "You need a signal to open this."
                : "No connection. Try again when you're back online."
        } catch {
            // Surface the real error so we can diagnose (network, decode, etc.).
            statusMessage = "Scan failed: \(error.localizedDescription)"
            print("[Wander] scan failed:", error)
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

            if teaser.isOwn {
                cacheOwnPin(
                    memoryID: teaser.memoryID,
                    lat: fix.lat,
                    lng: fix.lng,
                    dropDate: teaser.dropDate,
                    thumbnailURL: teaser.thumbnailURL
                )
            }
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
        } catch let error as LegacyAPIError where error.isConnectivityFailure {
            statusMessage = "You need a signal to open this."
        } catch {
            statusMessage = "Could not unlock. Try again when you have a signal."
        }
    }

    private func cacheOwnPin(
        memoryID: String,
        lat: Double,
        lng: Double,
        dropDate: String,
        thumbnailURL: String?
    ) {
        let pin = CachedOwnPin(
            memoryID: memoryID,
            lat: lat,
            lng: lng,
            dropDate: dropDate,
            thumbnailURL: thumbnailURL,
            cachedAt: Date()
        )
        OwnMemoryPinCache.save(pin)
        cachedOwnPins = OwnMemoryPinCache.load()
    }

    private func applyWarmth(from teasers: [Teaser]) {
        let level = WanderScanPolicy.maxWarmthLevel(from: teasers)
        warmthIntensity = level.intensity
        if level != previousWarmthLevel {
            haptics.playTransition(to: level)
            previousWarmthLevel = level
        }
    }

    /// Apply teasers from a background region-entry scan or proximity push refresh.
    public func ingestBackgroundScan(_ result: BackgroundRegionScanService.Result) {
        teasers = result.teasers
        if result.teasers.isEmpty {
            WanderScanCache.clear()
        } else {
            WanderScanCache.save(teasers: result.teasers)
        }
        applyWarmth(from: result.teasers)
        if result.hasInRangeMemory {
            statusMessage = "You're near a memory — open it when you're ready."
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
            #if os(iOS)
            if let coordinate = coordinator.userCoordinate {
                WanderUserMap(
                    coordinate: coordinate,
                    ownPins: coordinator.cachedOwnPins
                )
                .ignoresSafeArea()
            }
            #endif

            LegacyColor.background
                .opacity(coordinator.teasers.isEmpty ? 0.94 : 0.88)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                WanderHeaderBar(
                    warmthLevel: WarmthLevel(intensity: coordinator.warmthIntensity),
                    isScanning: coordinator.isScanning
                )
                .padding(.horizontal, LegacySpacing.lg)
                .padding(.top, LegacySpacing.sm)

                if coordinator.teasers.isEmpty {
                    WanderEmptyState()
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: LegacySpacing.md) {
                            ForEach(coordinator.teasers, id: \.memoryID) { teaser in
                                TeaserCard(teaser: teaser) {
                                    Task { await coordinator.unlock(teaser: teaser) }
                                }
                            }
                        }
                        .padding(.horizontal, LegacySpacing.lg)
                        .padding(.vertical, LegacySpacing.md)
                    }
                }

                if coordinator.isScanning || coordinator.isUnlocking {
                    ProgressView()
                        .tint(LegacyColor.accent)
                        .padding(.bottom, LegacySpacing.sm)
                }

                if let message = coordinator.statusMessage, !coordinator.isShowingUnlockedMedia {
                    Text(message)
                        .font(LegacyFont.callout)
                        .foregroundStyle(LegacyColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, LegacySpacing.lg)
                        .padding(.bottom, LegacySpacing.sm)
                }
            }
            .overlay(alignment: .bottom) {
                if coordinator.showsOfflineNearUX {
                    OfflineNearBanner()
                        .padding(.horizontal, LegacySpacing.lg)
                        .padding(.bottom, LegacySpacing.lg)
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

private struct WanderHeaderBar: View {
    let warmthLevel: WarmthLevel
    let isScanning: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: LegacySpacing.xxs) {
                Text("Wander")
                    .font(LegacyFont.title)
                    .foregroundStyle(LegacyColor.textPrimary)
                Text(subtitle)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
            }
            Spacer()
            if isScanning {
                ProgressView()
                    .tint(LegacyColor.accent)
            } else if warmthLevel != .none {
                WarmthBadge(level: warmthLevel)
            }
        }
    }

    private var subtitle: String {
        switch warmthLevel {
        case .none: return "Walk to discover memories"
        case .coarse: return "Something is in the area"
        case .approaching: return "Getting warmer"
        case .inBubble: return "Very close"
        }
    }
}

private struct WarmthBadge: View {
    let level: WarmthLevel

    var body: some View {
        Text(label)
            .font(LegacyFont.caption)
            .foregroundStyle(LegacyColor.textOnAccent)
            .padding(.horizontal, LegacySpacing.sm)
            .padding(.vertical, LegacySpacing.xxs)
            .background(LegacyColor.accent.opacity(0.9))
            .clipShape(Capsule())
    }

    private var label: String {
        switch level {
        case .none: return ""
        case .coarse: return "Nearby"
        case .approaching: return "Closer"
        case .inBubble: return "Here"
        }
    }
}

private struct WanderEmptyState: View {
    var body: some View {
        VStack(spacing: LegacySpacing.lg) {
            Image(systemName: "figure.walk")
                .font(.system(size: 44))
                .foregroundStyle(LegacyColor.accent.opacity(0.85))
            Text("Walk to discover")
                .font(LegacyFont.headline)
                .foregroundStyle(LegacyColor.textPrimary)
            Text("Memories appear as you move — no pins, no directions, just warmth.")
                .font(LegacyFont.callout)
                .foregroundStyle(LegacyColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LegacySpacing.xl)
        }
    }
}

private struct TeaserCard: View {
    let teaser: Teaser
    let onUnlock: () -> Void

    var body: some View {
        HStack(spacing: LegacySpacing.md) {
            teaserThumbnail

            VStack(alignment: .leading, spacing: LegacySpacing.xs) {
                Text(teaser.ownerDisplay == "you" ? "Your memory" : teaser.ownerDisplay)
                    .font(LegacyFont.headline)
                    .foregroundStyle(LegacyColor.textPrimary)
                Text(teaser.dropDate)
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
                HStack {
                    Label(
                        teaser.inRange ? "In range" : warmthLabel,
                        systemImage: teaser.inRange ? "location.fill" : "sparkles"
                    )
                    .font(LegacyFont.caption)
                    .foregroundStyle(teaser.inRange ? LegacyColor.accent : LegacyColor.textSecondary)
                    Spacer()
                    if teaser.inRange {
                        Button("Open", action: onUnlock)
                            .buttonStyle(.legacyPrimary)
                            .frame(maxWidth: 100)
                    }
                }
            }
        }
        .padding(LegacySpacing.md)
        .background(LegacyColor.surface.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: LegacyRadius.md)
                .stroke(LegacyColor.separator, lineWidth: 1)
        )
    }

    private var warmthLabel: String {
        switch WarmthLevel(contractValue: teaser.warmth) {
        case .inBubble: return "Very close"
        case .approaching: return "Nearby"
        case .coarse: return "In the area"
        case .none: return "Nearby"
        }
    }

    @ViewBuilder
    private var teaserThumbnail: some View {
        if let urlString = teaser.thumbnailURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholderThumb
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm))
        } else {
            placeholderThumb
        }
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: LegacyRadius.sm)
            .fill(LegacyColor.background)
            .frame(width: 64, height: 64)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(LegacyColor.textSecondary)
            }
    }
}

private struct OfflineNearBanner: View {
    var body: some View {
        HStack(spacing: LegacySpacing.sm) {
            Image(systemName: "wifi.slash")
            Text("You need a signal to open this.")
                .font(LegacyFont.callout)
        }
        .foregroundStyle(LegacyColor.textPrimary)
        .padding(LegacySpacing.md)
        .frame(maxWidth: .infinity)
        .background(LegacyColor.surface.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
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

#if os(iOS)
private struct WanderUserMap: View {
    let coordinate: CLLocationCoordinate2D
    let ownPins: [CachedOwnPin]

    @State private var position: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D, ownPins: [CachedOwnPin]) {
        self.coordinate = coordinate
        self.ownPins = ownPins
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(ownPins) { pin in
                Marker("Your memory", coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng))
                    .tint(LegacyColor.accent)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .allowsHitTesting(false)
        .onChange(of: coordinate.latitude) { _, _ in
            position = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
        }
    }
}
#endif
