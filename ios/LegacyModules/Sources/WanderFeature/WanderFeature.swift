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
            } else {
                teasers = []
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
                .opacity(0.92)
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

                Spacer(minLength: 0)
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

private struct TeaserRow: View {
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
        }
        .listRowBackground(LegacyColor.surface)
    }

    @ViewBuilder
    private var teaserThumbnail: some View {
        if let urlString = teaser.thumbnailURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "photo")
                        .foregroundStyle(LegacyColor.textSecondary)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm))
        } else {
            RoundedRectangle(cornerRadius: LegacyRadius.sm)
                .fill(LegacyColor.surface)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(LegacyColor.textSecondary)
                }
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
