import APIClient
import CoreLocation
import DesignSystem
import LocationEngine
import MemoryLaneFeature
import os
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
    private static let log = Logger(subsystem: "app.legacy.ios", category: "wander")
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

    /// Teasers from the latest scan — no coordinates unless `pin_revealed` (contract §4).
    public private(set) var teasers: [Teaser] = []
    public private(set) var isScanning = false
    public private(set) var isUnlocking = false
    public private(set) var statusMessage: String?
    public private(set) var unlockedMedia: [MemoryMediaItem] = []
    public private(set) var unlockedCaption: String?
    public private(set) var unlockedReturnCount: Int = 0
    public private(set) var unlockedDropDate: String?
    public private(set) var dwellRemainingSeconds: Int?

    /// Active dwell countdown task — cancelled when unlock succeeds or user dismisses.
    private var dwellCountdownTask: Task<Void, Never>?
    private var pendingDwellTeaser: Teaser?

    /// Own-memory pins unlocked in range — safe to render offline (never stores others' coords).
    public private(set) var cachedOwnPins: [CachedOwnPin]

    /// Precision-7 coarse zones from the latest scan — glow overlays only (no exact pins).
    public private(set) var zoneGlows: [ZoneGlowOverlay] = []

    /// Others' memories revealed within ~100m — coordinates come from scan only, never persisted.
    public private(set) var revealedOthersPins: [RevealedMemoryPin] = []

    /// When set, Wander map only shows these own-pin IDs (pin-drop animation).
    public private(set) var mapPinFilter: Set<String>?

    public func reloadOwnPins() {
        cachedOwnPins = OwnMemoryPinCache.load()
    }

    /// Seed the map from the authoritative owner list so *every* memory is always visible —
    /// even on a fresh install or new device, where the local drop/unlock cache is empty.
    /// Owner coordinates are returned by `GET /v1/memories`; DEC-15 governs others' pins only.
    public func hydrateOwnPins() async {
        var collected: [CachedOwnPin] = []
        var cursor: String?
        var pagesRemaining = 20  // defensive cap (~1000 memories at limit 50)
        do {
            repeat {
                let response = try await apiClient.listMemories(cursor: cursor)
                for item in response.memories {
                    guard let lat = item.lat, let lng = item.lng else { continue }
                    collected.append(
                        CachedOwnPin(
                            memoryID: item.memoryID,
                            lat: lat,
                            lng: lng,
                            dropDate: item.dropDate,
                            thumbnailURL: item.thumbnailURL,
                            cachedAt: Date()
                        )
                    )
                }
                cursor = response.nextCursor
                pagesRemaining -= 1
            } while cursor != nil && pagesRemaining > 0
        } catch {
            // Offline or transient failure — keep whatever is already cached so the map
            // still shows previously-seen pins. The next appear retries.
            return
        }
        OwnMemoryPinCache.reconcile(serverPins: collected)
        cachedOwnPins = OwnMemoryPinCache.load()
    }

    public func setMapPinFilter(_ ids: Set<String>?) {
        mapPinFilter = ids
    }

    public var mapOwnPins: [CachedOwnPin] {
        guard let filter = mapPinFilter else { return cachedOwnPins }
        return cachedOwnPins.filter { filter.contains($0.memoryID) }
    }

    /// Memory IDs eligible to unlock from the latest scan (`in_range: true`).
    public var inRangeMemoryIDs: Set<String> {
        Set(teasers.filter(\.inRange).map(\.memoryID))
    }

    public var inRangeCount: Int { inRangeMemoryIDs.count }

    /// Warmth with a floor when the user is physically in range — the API band can lag one scan.
    public var effectiveWarmthIntensity: Double {
        guard inRangeCount > 0 else { return warmthIntensity }
        return max(warmthIntensity, WarmthLevel.inBubble.intensity)
    }

    private var hadInRangeMemories = false
    public var warmthIntensity: Double = 0

    /// Latest user fix for map display only — never used to infer teaser direction.
    public private(set) var userCoordinate: CLLocationCoordinate2D?

    /// Passthrough so the view can react to permission grants and auto-rescan.
    /// (LocationEngine is @Observable, so reading this in a view body tracks changes.)
    public var locationAuthorizationStatus: CLAuthorizationStatus {
        locationEngine.authorizationStatus
    }

    /// True when the user actively denied/restricted location — offer a Settings deep-link.
    public var isLocationDenied: Bool {
        locationAuthorizationStatus == .denied || locationAuthorizationStatus == .restricted
    }

    public var isOffline: Bool { networkMonitor.isOffline }

    /// True when offline but still in a coarse-or-closer warmth band (DEC-29).
    public var showsOfflineNearUX: Bool {
        isOffline && WanderScanPolicy.maxWarmthLevel(from: teasers) != .none
    }

    public var isShowingUnlockedMedia: Bool { !unlockedMedia.isEmpty }

    public func dismissUnlockedMedia() {
        dwellCountdownTask?.cancel()
        dwellCountdownTask = nil
        dwellRemainingSeconds = nil
        pendingDwellTeaser = nil
        unlockedMedia = []
        unlockedCaption = nil
        unlockedReturnCount = 0
        unlockedDropDate = nil
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

            let appAttest = await AppAttestBridge.currentAssertion()
            let body = LocationRequest(
                lat: fix.lat,
                lng: fix.lng,
                accuracyM: fix.accuracyM,
                attestation: appAttest?.attestation,
                challengeToken: appAttest?.challengeToken
            )

            if let response = try await apiClient.scan(body) {
                applyScanResult(response)
            } else {
                teasers = []
                zoneGlows = []
                revealedOthersPins = []
                WanderScanCache.clear()
            }

            applyWarmth(from: teasers)
            notifyInRangeDiscoveryIfNeeded()

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
            statusMessage = "Scan failed: \(error.localizedDescription)"
            Self.log.error("scan failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Attempt unlock for a teaser pin. Handles dwell-required UX messaging.
    public func unlock(teaser: Teaser) async {
        guard !isUnlocking else { return }

        isUnlocking = true
        statusMessage = nil
        unlockedMedia = []
        unlockedCaption = nil
        dwellCountdownTask?.cancel()
        dwellRemainingSeconds = nil
        pendingDwellTeaser = nil
        defer { isUnlocking = false }

        do {
            let fix = try await locationEngine.acquireFix()
            let appAttest = await AppAttestBridge.currentAssertion()
            let body = LocationRequest(
                lat: fix.lat,
                lng: fix.lng,
                accuracyM: fix.accuracyM,
                attestation: appAttest?.attestation,
                challengeToken: appAttest?.challengeToken
            )
            let response = try await apiClient.unlock(memoryID: teaser.memoryID, body)

            unlockedMedia = response.media.enumerated().map { index, item in
                MemoryMediaItem(
                    url: item.url,
                    thumbnailURL: nil,
                    type: item.type,
                    position: item.position ?? index
                )
            }
            .sorted { $0.position < $1.position }
            unlockedCaption = response.caption
            unlockedReturnCount = response.returnCount
            unlockedDropDate = response.dropDate
            statusMessage = nil
            pendingDwellTeaser = nil

            LegacyHaptics.unlockCeremony(isFirstReturn: response.returnCount <= 1)

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
                pendingDwellTeaser = teaser
                if let seconds = info.retryAfterSeconds {
                    startDwellCountdown(seconds: seconds, teaser: teaser)
                }
            case "not_in_range":
                statusMessage = "Walk closer to open this memory."
            case "sealed", "condition_unmet":
                statusMessage = message
            default:
                statusMessage = message
            }
        } catch let error as LegacyAPIError where error.isAppAttestFailure {
            statusMessage = "Device attestation failed. Reopen Legacy and try again on a real device."
        } catch LegacyAPIError.unauthorized {
            statusMessage = "Session expired. Sign out and sign in again."
        } catch let error as LegacyAPIError where error.isConnectivityFailure {
            statusMessage = "You need a signal to open this."
        } catch {
            statusMessage = "Could not unlock. Try again when you have a signal."
        }
    }

    private func startDwellCountdown(seconds: Int, teaser: Teaser) {
        dwellCountdownTask?.cancel()
        dwellRemainingSeconds = seconds
        pendingDwellTeaser = teaser
        dwellCountdownTask = Task { [weak self] in
            guard let self else { return }
            var remaining = seconds
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
                if !Task.isCancelled {
                    self.dwellRemainingSeconds = max(remaining, 0)
                }
            }
            guard !Task.isCancelled else { return }
            self.dwellRemainingSeconds = nil
            guard self.pendingDwellTeaser?.memoryID == teaser.memoryID else { return }
            await self.unlock(teaser: teaser)
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
        zoneGlows = ZoneGlowOverlay.build(from: result.zones)
        revealedOthersPins = PinRevealPolicy.revealedOthers(from: result.teasers)
        if result.teasers.isEmpty {
            WanderScanCache.clear()
        } else {
            WanderScanCache.save(teasers: result.teasers)
        }
        applyWarmth(from: result.teasers)
        notifyInRangeDiscoveryIfNeeded()
        if result.hasInRangeMemory {
            statusMessage = "You're near a memory — open it when you're ready."
        }
    }

    private func applyScanResult(_ response: ScanResponse) {
        teasers = response.teasers
        zoneGlows = ZoneGlowOverlay.build(from: response.zones)
        revealedOthersPins = PinRevealPolicy.revealedOthers(from: response.teasers)
        WanderScanCache.save(teasers: response.teasers)
        cacheCoarseZones(response.zones)
    }

    private func cacheCoarseZones(_ zones: [CoarseZone]) {
        let records = zones.compactMap { zone -> CoarseZoneRecord? in
            guard let decoded = GeohashCell.decode(prefix: zone.geohashPrefix) else { return nil }
            return CoarseZoneRecord(
                geohashPrefix: zone.geohashPrefix,
                centerLat: decoded.lat,
                centerLng: decoded.lng
            )
        }
        CoarseZoneCache.merge(prefixes: records)
    }

    private func notifyInRangeDiscoveryIfNeeded() {
        let inRange = inRangeCount > 0
        if inRange, !hadInRangeMemories {
            LegacyHaptics.selection()
        }
        hadInRangeMemories = inRange
    }
}

public struct WanderFeatureRootView: View {
    public init(
        coordinator: WanderCoordinator,
        mutedZones: [MutedZone] = [],
        pinCelebration: PinDropCelebrationCoordinator? = nil,
        onStartDropping: (() -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.mutedZones = mutedZones
        self.pinCelebration = pinCelebration
        self.onStartDropping = onStartDropping
    }

    @Bindable private var coordinator: WanderCoordinator
    private let mutedZones: [MutedZone]
    private var pinCelebration: PinDropCelebrationCoordinator?
    private let onStartDropping: (() -> Void)?
    @State private var showsWalkHint = true
    @State private var trayExpanded = true
    /// Once the user taps "Got it" the walk hint never auto-returns. Persisted so it
    /// stays gone across tab switches and app launches (fixes "it comes over every
    /// time I go back to Wander").
    @AppStorage("legacyHasDismissedWalkHint") private var hasDismissedWalkHint = false
    @State private var discoveryToast: LegacyToast?
    @State private var isFollowingUser = true

    private var inRangeTeasers: [Teaser] { coordinator.teasers.filter(\.inRange) }

    private var showsDiscoveryHint: Bool {
        coordinator.teasers.isEmpty
            && showsWalkHint
            && !hasDismissedWalkHint
            // Don't cover the screen while a drop celebration is playing — that switch
            // to Wander is what made the hint "come over" mid-drop.
            && !(pinCelebration?.isActive ?? false)
    }

    public var body: some View {
        ZStack {
            #if os(iOS)
            if let coordinate = coordinator.userCoordinate {
                // MapLibre swap (dev/maplibre-wander-map): immersive custom-styled,
                // heading-locked map. The old MapKit `WanderUserMap` is kept below,
                // unused, for instant A/B comparison and revert.
                MapLibreWanderMap(
                    coordinate: coordinate,
                    ownPins: coordinator.mapOwnPins,
                    revealedOthersPins: coordinator.revealedOthersPins,
                    zoneGlows: coordinator.zoneGlows,
                    mutedZones: mutedZones,
                    inRangeMemoryIDs: coordinator.inRangeMemoryIDs,
                    isFollowingUser: $isFollowingUser
                )
                .ignoresSafeArea()
            } else {
                WanderMapSkeleton()
                    .ignoresSafeArea()
            }
            #endif

            WanderMapAtmosphere(showsWalkHint: showsWalkHint)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                WanderHeaderBar(
                    warmthLevel: WarmthLevel(intensity: coordinator.effectiveWarmthIntensity),
                    isScanning: coordinator.isScanning,
                    showsDiscoveryHint: showsDiscoveryHint
                )
                .padding(.horizontal, LegacySpacing.lg)
                .padding(.top, LegacySpacing.sm)

                if coordinator.inRangeCount > 0, !coordinator.isShowingUnlockedMedia {
                    InRangePresenceBanner(count: coordinator.inRangeCount)
                        .padding(.horizontal, LegacySpacing.lg)
                        .padding(.top, LegacySpacing.xs)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showsDiscoveryHint {
                    WanderEmptyState(
                        onStartDropping: onStartDropping,
                        onDismiss: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            hasDismissedWalkHint = true
                            showsWalkHint = false
                        }
                    })
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    // Map-first: leave the middle open so the map stays pannable.
                    // A Spacer has no hit-testable content, so touches here fall
                    // through to the Map behind it (fixes concern-forced-unlock-annoying).
                    Spacer(minLength: 0)
                }

                if coordinator.isScanning || coordinator.isUnlocking {
                    ProgressView()
                        .tint(LegacyColor.accent)
                        .padding(.bottom, LegacySpacing.sm)
                }

                if let seconds = coordinator.dwellRemainingSeconds, !coordinator.isShowingUnlockedMedia {
                    #if os(iOS)
                    DwellProgressRing(remainingSeconds: seconds)
                        .padding(.bottom, LegacySpacing.md)
                    #endif
                }

                if let message = coordinator.statusMessage, !coordinator.isShowingUnlockedMedia,
                   coordinator.dwellRemainingSeconds == nil {
                    Text(message)
                        .font(LegacyFont.callout)
                        .foregroundStyle(LegacyColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, LegacySpacing.lg)
                        .padding(.bottom, LegacySpacing.sm)
                }

                #if os(iOS)
                if coordinator.isLocationDenied {
                    OpenSettingsButton()
                        .padding(.horizontal, LegacySpacing.xl)
                        .padding(.bottom, LegacySpacing.sm)
                }
                #endif

                if !inRangeTeasers.isEmpty {
                    WanderTeaserTray(
                        teasers: inRangeTeasers,
                        isExpanded: $trayExpanded
                    ) { teaser in
                        Task { await coordinator.unlock(teaser: teaser) }
                    }
                    .padding(.horizontal, LegacySpacing.sm)
                    .padding(.bottom, LegacySpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: inRangeTeasers.isEmpty)
            .overlay(alignment: .bottom) {
                if let celebration = pinCelebration,
                   let message = celebration.overlayMessage,
                   let progress = celebration.overlayProgress {
                    PinDropCelebrationOverlay(message: message, progress: progress)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if coordinator.showsOfflineNearUX {
                    OfflineNearBanner()
                        .padding(.horizontal, LegacySpacing.lg)
                        .padding(.bottom, LegacySpacing.lg)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: pinCelebration?.isActive ?? false)

            WarmthCueOverlay(intensity: coordinator.effectiveWarmthIntensity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if !isFollowingUser {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) { isFollowingUser = true }
                        } label: {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(LegacyColor.accent)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                        }
                        .padding(.trailing, LegacySpacing.lg)
                        .padding(.bottom, 160)
                    }
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFollowingUser)
        .animation(.easeInOut(duration: 0.35), value: coordinator.inRangeCount)
        .animation(.easeOut(duration: 0.45), value: showsWalkHint)
        .task(id: coordinator.teasers.isEmpty) {
            guard coordinator.teasers.isEmpty, !hasDismissedWalkHint else {
                showsWalkHint = false
                return
            }
            showsWalkHint = true
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            showsWalkHint = false
        }
        .task {
            await coordinator.scanIfNeeded(force: true)
        }
        .task {
            // Belt-and-braces: if a prior pin-drop celebration was interrupted, its filter
            // could still be hiding pins. Clear it unless a celebration is currently running.
            if !(pinCelebration?.isActive ?? false) {
                coordinator.setMapPinFilter(nil)
            }
            await coordinator.hydrateOwnPins()
        }
        // Auto-relock is owned by the map coordinator now (idle-debounced: 6 s after the
        // *last* gesture, not 6 s after follow was first lost). See MapLibreWanderMap.
        #if os(iOS)
        .onChange(of: coordinator.isShowingUnlockedMedia) { wasShowing, isShowing in
            if !wasShowing, isShowing, coordinator.unlockedReturnCount <= 1 {
                discoveryToast = LegacyToast(
                    message: UnlockReturnNarrative.firstDiscoveryToast(),
                    style: .success
                )
            }
        }
        .onChange(of: coordinator.locationAuthorizationStatus) { _, status in
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                Task { await coordinator.scanIfNeeded(force: true) }
            }
        }
        .onChange(of: coordinator.inRangeCount) { wasInRange, isInRange in
            if wasInRange == 0, isInRange > 0 {
                withAnimation(.easeInOut(duration: 0.28)) { trayExpanded = true }
            }
        }
        .legacyToast($discoveryToast)
        .sheet(isPresented: Binding(
            get: { coordinator.isShowingUnlockedMedia },
            set: { if !$0 { coordinator.dismissUnlockedMedia() } }
        )) {
            if !coordinator.unlockedMedia.isEmpty {
                UnlockedMemorySheet(
                    photos: coordinator.unlockedMedia,
                    caption: coordinator.unlockedCaption,
                    returnCount: coordinator.unlockedReturnCount,
                    dropDate: coordinator.unlockedDropDate
                )
            }
        }
        #endif
    }

}

/// Edge vignette + warm ground glow — lets the map breathe instead of a flat dark wash.
private struct WanderMapAtmosphere: View {
    let showsWalkHint: Bool

    var body: some View {
        GeometryReader { proxy in
            let maxDim = max(proxy.size.width, proxy.size.height)
            ZStack {
                if showsWalkHint {
                    LegacyColor.background.opacity(0.94)
                } else {
                    RadialGradient(
                        colors: [
                            .clear,
                            LegacyColor.background.opacity(0.18),
                            LegacyColor.background.opacity(0.52),
                        ],
                        center: .center,
                        startRadius: maxDim * 0.22,
                        endRadius: maxDim * 0.78
                    )
                    LinearGradient(
                        colors: [
                            LegacyColor.background.opacity(0.28),
                            .clear,
                            LegacyColor.accent.opacity(0.07),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
    }
}

private struct WanderHeaderBar: View {
    let warmthLevel: WarmthLevel
    let isScanning: Bool
    var showsDiscoveryHint: Bool = false

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
        case .none:
            return showsDiscoveryHint ? "Walk to discover memories" : "Keep wandering"
        case .coarse: return "Something is in the area"
        case .approaching: return "Getting warmer"
        case .inBubble: return "Very close"
        }
    }
}

/// Shown when `/scan` reports `in_range` — the pin may sit under the user puck, so the map
/// needs an explicit “you’re here” signal beyond the bottom teaser tray.
private struct InRangePresenceBanner: View {
    let count: Int
    @State private var glow = false

    var body: some View {
        HStack(spacing: LegacySpacing.sm) {
            Image(systemName: "location.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(LegacyColor.accent)
                .symbolEffect(.pulse, options: .repeating, value: glow)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(LegacyFont.headline)
                    .foregroundStyle(LegacyColor.textPrimary)
                Text("Tap Open below — the pin is right under you.")
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LegacySpacing.md)
        .padding(.vertical, LegacySpacing.sm)
        .background(LegacyColor.surface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: LegacyRadius.md)
                .stroke(LegacyColor.accent.opacity(glow ? 0.55 : 0.25), lineWidth: 1.5)
        )
        .shadow(color: LegacyColor.accent.opacity(0.2), radius: glow ? 14 : 6)
        .onAppear { glow = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headline)
        .accessibilityHint("Expand nearby memories and tap Open to unlock.")
    }

    private var headline: String {
        count == 1 ? "You're standing on a memory" : "\(count) memories underfoot"
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
    let onStartDropping: (() -> Void)?
    let onDismiss: () -> Void

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

            if let onStartDropping {
                Button("Drop your first memory", action: onStartDropping)
                    .buttonStyle(.legacyPrimary)
                    .padding(.horizontal, LegacySpacing.xl)
            }

            Button("Got it", action: onDismiss)
                .font(LegacyFont.callout.weight(.semibold))
                .foregroundStyle(LegacyColor.accent)
                .padding(.top, LegacySpacing.xs)
                .accessibilityHint("Hides this tip for good")
        }
    }
}

/// Collapsible bottom tray for nearby memory teasers. Bounded height so the map
/// above it stays visible and pannable; the user chooses when to engage a pin.
private struct WanderTeaserTray: View {
    let teasers: [Teaser]
    @Binding var isExpanded: Bool
    let onUnlock: (Teaser) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.28)) { isExpanded.toggle() }
            } label: {
                VStack(spacing: LegacySpacing.xs) {
                    Capsule()
                        .fill(LegacyColor.separator)
                        .frame(width: 36, height: 5)
                        .padding(.top, LegacySpacing.sm)

                    HStack(spacing: LegacySpacing.sm) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(LegacyColor.accent)
                        Text(summary)
                            .font(LegacyFont.headline)
                            .foregroundStyle(LegacyColor.textPrimary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    }
                    .padding(.horizontal, LegacySpacing.lg)
                    .padding(.bottom, LegacySpacing.sm)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse nearby memories" : "Expand nearby memories")

            if isExpanded {
                ScrollView {
                    LazyVStack(spacing: LegacySpacing.md) {
                        ForEach(teasers, id: \.memoryID) { teaser in
                            TeaserCard(teaser: teaser) { onUnlock(teaser) }
                        }
                    }
                    .padding(.horizontal, LegacySpacing.lg)
                    .padding(.bottom, LegacySpacing.md)
                }
                .frame(maxHeight: 300)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: LegacyRadius.lg)
                .stroke(LegacyColor.separator, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: -2)
    }

    private var summary: String {
        teasers.count == 1 ? "1 memory in range" : "\(teasers.count) memories in range"
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
                    Label("In range", systemImage: "location.fill")
                        .font(LegacyFont.caption)
                        .foregroundStyle(LegacyColor.accent)
                    Spacer()
                    Button("Open", action: onUnlock)
                        .buttonStyle(.legacyPrimary)
                        .frame(maxWidth: 100)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(teaser.ownerDisplay == "you" ? "Your memory" : teaser.ownerDisplay), dropped \(teaser.dropDate), in range to open")
        .accessibilityHint("Double tap Open to unlock")
    }

    @ViewBuilder
    private var teaserThumbnail: some View {
        if let urlString = teaser.thumbnailURL, let url = TrustedMediaURL.mediaURL(from: urlString) {
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
    let photos: [MemoryMediaItem]
    let caption: String?
    let returnCount: Int
    let dropDate: String?

    @Environment(\.dismiss) private var dismiss
    @State private var revealProgress = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LegacySpacing.lg) {
                    VStack(spacing: LegacySpacing.xxs) {
                        Text(UnlockReturnNarrative.headline(returnCount: returnCount))
                            .font(LegacyFont.headline)
                            .foregroundStyle(LegacyColor.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(UnlockReturnNarrative.subtitle(returnCount: returnCount, dropDate: dropDate))
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    MemoryPhotoGallery(photos: photos)
                        .opacity(revealProgress ? 1 : 0.6)
                        .scaleEffect(revealProgress ? 1 : 0.97)
                        .animation(LegacyMotion.animation(.easeOut(duration: 0.55)), value: revealProgress)

                    if let caption, !caption.isEmpty {
                        Text(caption)
                            .font(LegacyFont.body)
                            .foregroundStyle(LegacyColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(LegacySpacing.lg)
            }
            .background(
                LinearGradient(
                    colors: [LegacyColor.background, LegacyColor.surface.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle("Memory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if LegacyMotion.isReduced {
                revealProgress = true
            } else {
                revealProgress = false
                withAnimation(.easeOut(duration: 0.55)) { revealProgress = true }
            }
        }
    }
}

private struct WanderMapSkeleton: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [LegacyColor.background, LegacyColor.surface.opacity(0.65)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: LegacySpacing.md) {
                RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous)
                    .fill(LegacyColor.surface.opacity(0.65))
                    .frame(width: 220, height: 18)
                RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous)
                    .fill(LegacyColor.surface.opacity(0.65))
                    .frame(width: 180, height: 14)
            }
            .legacyShimmer()
        }
    }
}

#if os(iOS)
private struct WanderUserMap: View {
    let coordinate: CLLocationCoordinate2D
    let ownPins: [CachedOwnPin]
    let revealedOthersPins: [RevealedMemoryPin]
    let zoneGlows: [ZoneGlowOverlay]

    @State private var position: MapCameraPosition
    @State private var visibleOwnPinIDs: Set<String> = []
    @State private var visibleRevealedPinIDs: Set<String> = []

    init(
        coordinate: CLLocationCoordinate2D,
        ownPins: [CachedOwnPin],
        revealedOthersPins: [RevealedMemoryPin],
        zoneGlows: [ZoneGlowOverlay]
    ) {
        self.coordinate = coordinate
        self.ownPins = ownPins
        self.revealedOthersPins = revealedOthersPins
        self.zoneGlows = zoneGlows
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            ForEach(zoneGlows) { zone in
                MapCircle(
                    center: CLLocationCoordinate2D(latitude: zone.centerLat, longitude: zone.centerLng),
                    radius: zone.radiusMeters
                )
                .foregroundStyle(LegacyColor.accent.opacity(zone.opacity))
            }

            ForEach(ownPins) { pin in
                Annotation("Your memory", coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)) {
                    PinDropMarker(isVisible: visibleOwnPinIDs.contains(pin.memoryID), style: .own)
                }
            }

            ForEach(revealedOthersPins) { pin in
                Annotation("Memory nearby", coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)) {
                    PinDropMarker(isVisible: visibleRevealedPinIDs.contains(pin.memoryID), style: .revealed)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onAppear {
            syncVisiblePins(animated: false)
            fitCamera()
        }
        .onChange(of: ownPins.map(\.memoryID)) { oldIDs, newIDs in
            guard oldIDs != newIDs else { return }
            let incoming = ownPins.filter { !visibleOwnPinIDs.contains($0.memoryID) }.map(\.memoryID)
            staggerReveal(incoming: incoming) { visibleOwnPinIDs.insert($0) }
            visibleOwnPinIDs = visibleOwnPinIDs.intersection(Set(newIDs))
        }
        .onChange(of: revealedOthersPins.map(\.memoryID)) { oldIDs, newIDs in
            guard oldIDs != newIDs else { return }
            let incoming = revealedOthersPins.filter { !visibleRevealedPinIDs.contains($0.memoryID) }.map(\.memoryID)
            staggerReveal(incoming: incoming) { visibleRevealedPinIDs.insert($0) }
            visibleRevealedPinIDs = visibleRevealedPinIDs.intersection(Set(newIDs))
        }
        // Debounce camera fitting: the import cascade grows the pin set one pin at a
        // time (~80ms apart). Fitting per pin fired dozens of overlapping camera
        // animations (the "glitchy" import). Coalesce into one fit after pins settle.
        .task(id: cameraFitKey) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            fitCamera()
        }
    }

    private var cameraFitKey: String {
        ownPins.map(\.memoryID).joined(separator: ",")
            + "|" + revealedOthersPins.map(\.memoryID).joined(separator: ",")
    }

    /// Reveal newly-arrived pins with a capped stagger. The first `staggerCap` pins
    /// animate in sequence; any beyond that drop together so a large batch (e.g. a
    /// cold-launch cache of dozens of pins) never animates enough markers to drop frames.
    private func staggerReveal(incoming: [String], insert: @escaping (String) -> Void) {
        guard !incoming.isEmpty else { return }
        // Reduce Motion: drop every pin in at once with no spring or cascade.
        if LegacyMotion.isReduced {
            withAnimation(nil) { incoming.forEach(insert) }
            return
        }
        let staggerCap = 12
        for (index, pinID) in incoming.enumerated() {
            let delay = Double(min(index, staggerCap)) * 0.08
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                    insert(pinID)
                }
            }
        }
    }

    private func syncVisiblePins(animated: Bool) {
        if animated && !LegacyMotion.isReduced {
            visibleOwnPinIDs = []
            visibleRevealedPinIDs = []
            for (index, pinID) in ownPins.map(\.memoryID).enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                        _ = visibleOwnPinIDs.insert(pinID)
                    }
                }
            }
            for (index, pinID) in revealedOthersPins.map(\.memoryID).enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.08) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                        _ = visibleRevealedPinIDs.insert(pinID)
                    }
                }
            }
        } else {
            visibleOwnPinIDs = Set(ownPins.map(\.memoryID))
            visibleRevealedPinIDs = Set(revealedOthersPins.map(\.memoryID))
        }
    }

    private func fitCamera() {
        var points = [coordinate]
        points.append(contentsOf: ownPins.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        })
        points.append(contentsOf: revealedOthersPins.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        })
        let lats = points.map(\.latitude)
        let lngs = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.012, (maxLat - minLat) * 1.5 + 0.008),
            longitudeDelta: max(0.012, (maxLng - minLng) * 1.5 + 0.008)
        )
        withAnimation(LegacyMotion.animation(.easeInOut(duration: 0.45))) {
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

private struct PinDropMarker: View {
    enum Style {
        case own
        case revealed
    }

    let isVisible: Bool
    var style: Style = .own

    var body: some View {
        Image(systemName: style == .own ? "mappin.circle.fill" : "mappin.and.ellipse")
            .font(.system(size: style == .own ? 28 : 24, weight: .semibold))
            .foregroundStyle(style == .own ? LegacyColor.accent : LegacyColor.accent.opacity(0.85))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .scaleEffect(isVisible ? 1.0 : 0.01)
            .offset(y: isVisible ? 0 : -24)
            .opacity(isVisible ? 1 : 0)
            .animation(
                LegacyMotion.animation(.spring(response: 0.38, dampingFraction: 0.72)),
                value: isVisible
            )
    }
}
#endif
