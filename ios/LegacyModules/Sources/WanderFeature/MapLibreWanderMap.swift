#if os(iOS)
import APIClient
import CoreLocation
import DesignSystem
import LocationEngine
import MapLibre
import os
import SwiftUI
import UIKit

/// Immersive, art-directed replacement for the MapKit `WanderUserMap`.
///
/// Why this exists: MapKit can only render Apple's stock style, so the Wander map
/// read as "just Apple Maps." MapLibre renders custom vector-tile styles and gives us
/// a pitched, heading-locked follow camera — the "walking inside your own world" feel.
///
/// Tiles come from **OpenFreeMap** (https://openfreemap.org): community-hosted vector
/// tiles + styles, no API key, no signup, no billing. Base style is **Fiord** (dark);
/// `WanderMapStyle.applyLegacyTheme` warms the palette and strips label clutter at load.
///
/// This view is intentionally a drop-in for `WanderUserMap` (same init signature) so the
/// swap at the call site is one line and trivially reversible.
struct MapLibreWanderMap: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let ownPins: [CachedOwnPin]
    let revealedOthersPins: [RevealedMemoryPin]
    let zoneGlows: [ZoneGlowOverlay]
    let mutedZones: [MutedZone]
    let inRangeMemoryIDs: Set<String>
    @Binding var isFollowingUser: Bool
    /// Long-press on the map surface triggers a V1 drop at the user's current location.
    var onLongPress: (() -> Void)?
    /// Memory ID of the pin the coordinator wants the map to fly to before the sheet opens.
    var unlockFlyMemoryID: String?
    var unlockFlyTarget: CLLocationCoordinate2D?

    // MARK: UIViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = OffsetMLNMapView(frame: .zero, styleURL: WanderMapStyle.current)
        mapView.verticalBias = WanderMapStyle.userScreenBias
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView

        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.setCenter(coordinate, zoomLevel: WanderMapStyle.streetZoom, animated: false)

        mapView.logoView.isHidden = false
        mapView.compassView.compassVisibility = .adaptive
        mapView.allowsRotating = true
        mapView.allowsTilting = true

        // Long-press anywhere on the map surface → V1 "I'm here" drop at current location.
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMapLongPress(_:))
        )
        longPress.minimumPressDuration = 0.65
        mapView.addGestureRecognizer(longPress)

        context.coordinator.pendingInitialPitch = WanderMapStyle.pitch
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.inRangeMemoryIDs = inRangeMemoryIDs
        context.coordinator.onTrackingLost = {
            withAnimation(.easeInOut(duration: 0.2)) { isFollowingUser = false }
        }
        context.coordinator.onRelock = {
            withAnimation(.easeInOut(duration: 0.4)) { isFollowingUser = true }
        }
        if isFollowingUser && mapView.userTrackingMode == .none {
            mapView.setUserTrackingMode(.followWithHeading, animated: true)
        }
        context.coordinator.syncZoneGlows(zoneGlows, on: mapView)
        context.coordinator.syncMutedZones(mutedZones, on: mapView)
        context.coordinator.syncInRangeHalos(ownPins: ownPins, on: mapView)
        context.coordinator.syncPins(
            own: ownPins,
            revealed: revealedOthersPins,
            on: mapView
        )
        context.coordinator.onLongPress = onLongPress

        // Seed an offline tile pack for the current neighbourhood once per session.
        context.coordinator.scheduleOfflineCacheIfNeeded(for: coordinate)

        // Fly the camera to the unlocked pin location before the media sheet opens.
        if let memID = unlockFlyMemoryID,
           memID != context.coordinator.lastFlyMemoryID,
           let target = unlockFlyTarget {
            context.coordinator.lastFlyMemoryID = memID
            // Release the follow camera first — otherwise the next location update
            // snaps the camera back to the user mid-flight. The idle relock timer
            // (armed by the tracking-mode change) restores follow afterwards.
            if mapView.userTrackingMode != .none {
                mapView.setUserTrackingMode(.none, animated: false)
            }
            let flyCamera = MLNMapCamera(
                lookingAtCenter: target,
                altitude: 300,
                pitch: WanderMapStyle.pitch,
                heading: mapView.camera.heading
            )
            mapView.fly(to: flyCamera, withDuration: 0.85, peakAltitude: 400, completionHandler: nil)
        }
        if unlockFlyMemoryID == nil {
            context.coordinator.lastFlyMemoryID = nil
        }
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: Coordinator) {
        coordinator.stopPulse()
        mapView.delegate = nil
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MLNMapViewDelegate {
        private static let log = Logger(subsystem: "app.legacy.ios", category: "wander-map")
        weak var mapView: MLNMapView?
        var pendingInitialPitch: CGFloat?
        var inRangeMemoryIDs: Set<String> = []
        var onTrackingLost: (() -> Void)?
        var onRelock: (() -> Void)?
        var onLongPress: (() -> Void)?
        var lastFlyMemoryID: String?
        private var hasScheduledOfflinePack = false
        private var relockTimer: Timer?
        private var lastInteractionTime: CFTimeInterval = 0
        private static let relockAfterIdle: TimeInterval = 6

        private var zoneSource: MLNShapeSource?
        private var mutedZoneSource: MLNShapeSource?
        private var inRangeSource: MLNShapeSource?
        private var inRangeFillLayer: MLNFillStyleLayer?
        private var inRangeRingLayer: MLNLineStyleLayer?
        private var heatmapSource: MLNShapeSource?
        private var renderedZoneIDs: [String] = []
        private var renderedMutedZoneIDs: [String] = []
        private var renderedInRangeKey = ""
        private var renderedHeatmapPinIDs: [String] = []
        private var renderedPinStates: [PinRenderState] = []
        /// Live annotations keyed by memory ID — enables in-place diffing so a state
        /// change on one pin no longer churns every annotation view on the map.
        private var pinAnnotationsByID: [String: PinAnnotation] = [:]
        private var pulseTimer: Timer?
        private var pulsePhase: CGFloat = 0

        /// Latest overlay inputs — reapplied when the vector style finishes (or reloads).
        private var latestZoneGlows: [ZoneGlowOverlay] = []
        private var latestMutedZones: [MutedZone] = []
        private var latestOwnPins: [CachedOwnPin] = []
        private var latestRevealedPins: [RevealedMemoryPin] = []

        private static let ownReuseID = "legacy.pin.own"
        private static let revealedReuseID = "legacy.pin.revealed"
        private static let userPuckReuseID = "legacy.user.puck"
        private static let inRangeHaloRadiusMeters: Double = 48

        private static let zoneSourceID = "legacy.zones"
        private static let zoneFillLayerID = "legacy.zones.fill"
        private static let mutedZoneSourceID = "legacy.muted-zones"
        private static let mutedZoneFillLayerID = "legacy.muted-zones.fill"
        private static let inRangeSourceID = "legacy.inrange"
        private static let inRangeFillLayerID = "legacy.inrange.fill"
        private static let inRangeRingLayerID = "legacy.inrange.ring"
        private static let heatmapSourceID = "legacy.heatmap"
        private static let heatmapLayerID = "legacy.heatmap.density"

        private struct PinRenderState: Equatable {
            let memoryID: String
            let style: PinAnnotation.Style
            let inRange: Bool
        }

        deinit {
            pulseTimer?.invalidate()
            relockTimer?.invalidate()
        }

        func stopPulse() {
            pulseTimer?.invalidate()
            pulseTimer = nil
        }

        // MARK: Long-press drop

        @objc func handleMapLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            // Gesture recognizers always call back on the main thread.
            MainActor.assumeIsolated {
                LegacyHaptics.selection()
            }
            onLongPress?()
        }

        // MARK: Offline tile cache

        /// Downloads vector tiles for a ~1.5 km radius around the user's first known
        /// location each session. Subsequent offline Wander visits render the basemap
        /// without a network connection (hiking / travel drops).
        ///
        /// Skips the download when an existing pack already covers the coordinate, and
        /// caps total stored packs (evicting oldest first) so storage stays bounded.
        private static let maxOfflinePacks = 6

        func scheduleOfflineCacheIfNeeded(for coordinate: CLLocationCoordinate2D) {
            guard !hasScheduledOfflinePack else { return }
            // `packs` is nil until MLNOfflineStorage finishes its async load — leave the
            // flag unset so a later updateUIView retries once the inventory is available.
            guard let existingPacks = MLNOfflineStorage.shared.packs else { return }
            hasScheduledOfflinePack = true

            // Already covered by a previous session's pack for this style? Done.
            for pack in existingPacks {
                if let region = pack.region as? MLNTilePyramidOfflineRegion,
                   region.styleURL == WanderMapStyle.current,
                   region.bounds.sw.latitude <= coordinate.latitude,
                   coordinate.latitude <= region.bounds.ne.latitude,
                   region.bounds.sw.longitude <= coordinate.longitude,
                   coordinate.longitude <= region.bounds.ne.longitude {
                    return
                }
            }

            // Evict oldest packs (context stores creation date) to stay under the cap.
            let dated = existingPacks.map { pack -> (MLNOfflinePack, Date) in
                let date = (try? JSONDecoder().decode(Date.self, from: pack.context)) ?? .distantPast
                return (pack, date)
            }
            .sorted { $0.1 < $1.1 }
            let excess = dated.count - (Self.maxOfflinePacks - 1)
            if excess > 0 {
                for (pack, _) in dated.prefix(excess) {
                    MLNOfflineStorage.shared.removePack(pack, withCompletionHandler: nil)
                }
            }

            let deg: CLLocationDegrees = 0.013  // ≈ 1.5 km
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(
                    latitude: coordinate.latitude - deg,
                    longitude: coordinate.longitude - deg * 1.4
                ),
                ne: CLLocationCoordinate2D(
                    latitude: coordinate.latitude + deg,
                    longitude: coordinate.longitude + deg * 1.4
                )
            )
            let region = MLNTilePyramidOfflineRegion(
                styleURL: WanderMapStyle.current,
                bounds: bounds,
                fromZoomLevel: 12,
                toZoomLevel: 17
            )
            let context = (try? JSONEncoder().encode(Date())) ?? Data()
            MLNOfflineStorage.shared.addPack(for: region, withContext: context) { pack, _ in
                pack?.resume()
            }
        }

        // MARK: Auto-relock (re-follow after the user goes idle)

        /// Mark "the user just did something." Cheap (timestamp only) so it's safe to call
        /// every frame from `mapViewRegionIsChanging` without the per-frame timer churn that
        /// was contributing to the pan stutter.
        private func noteInteraction() {
            lastInteractionTime = CACurrentMediaTime()
        }

        /// Arm the idle→relock clock (called once when follow is first lost). A single
        /// self-rescheduling timer measures time since the *last* interaction, so the map
        /// only re-follows after you actually stop touching for 6 s — not 6 s after follow
        /// was first lost, and never mid-gesture even on a long continuous drag.
        private func scheduleRelock(on mapView: MLNMapView) {
            noteInteraction()
            guard relockTimer == nil else { return }
            armRelockTimer(on: mapView, after: Self.relockAfterIdle)
        }

        private func armRelockTimer(on mapView: MLNMapView, after interval: TimeInterval) {
            relockTimer?.invalidate()
            relockTimer = Timer.scheduledTimer(
                withTimeInterval: interval,
                repeats: false
            ) { [weak self, weak mapView] _ in
                guard let self, let mapView else { return }
                self.relockTimer = nil
                guard mapView.userTrackingMode == .none else { return }
                let idle = CACurrentMediaTime() - self.lastInteractionTime
                if idle >= Self.relockAfterIdle - 0.1 {
                    mapView.setUserTrackingMode(.followWithHeading, animated: true)
                    self.onRelock?()
                } else {
                    // Interaction happened while waiting — wait out the remainder.
                    self.armRelockTimer(on: mapView, after: Self.relockAfterIdle - idle)
                }
            }
        }

        private func cancelRelock() {
            relockTimer?.invalidate()
            relockTimer = nil
        }

        // MARK: Style lifecycle

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            WanderMapStyle.applyLegacyTheme(to: style)
            if let pitch = pendingInitialPitch {
                let camera = mapView.camera
                camera.pitch = pitch
                mapView.setCamera(camera, animated: false)
                pendingInitialPitch = nil
            }
            resetOverlaySources()
            ensureHeatmapLayer(on: style)    // first = below all other custom layers
            ensureZoneLayer(on: style)
            ensureMutedZoneLayer(on: style)
            ensureInRangeLayer(on: style)
            applyStoredOverlayState(on: mapView)
        }

        func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
            if mode == .none {
                onTrackingLost?()
                scheduleRelock(on: mapView)
            } else {
                cancelRelock()
                // setUserTrackingMode resets pitch to 0 — restore the zoom-appropriate
                // tilt after every re-lock (full tilt at street level, flatter when zoomed out).
                let target = WanderMapStyle.pitch(forZoom: mapView.zoomLevel)
                let camera = mapView.camera
                guard abs(camera.pitch - target) > 1 else { return }
                camera.pitch = target
                mapView.setCamera(camera, withDuration: 0.35, animationTimingFunction: nil)
            }
        }

        /// Continuously ramp camera tilt to match zoom while the map moves. Flattening the
        /// pitch as the user zooms out is what stops the puck swimming near the horizon.
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            // While the map is un-followed, every move resets the idle countdown (cheap
            // timestamp write — the timer itself was armed when follow was lost).
            if mapView.userTrackingMode == .none {
                noteInteraction()
            }

            // Only manage tilt within/below the ramp band. Above street zoom the target is a
            // constant 58°, so re-issuing setCamera mid-pan there just fights the gesture and
            // judders the whole map — leave the camera alone when zoomed in tight.
            guard mapView.zoomLevel < WanderMapStyle.fullPitchZoom else { return }
            let target = WanderMapStyle.pitch(forZoom: mapView.zoomLevel)
            let camera = mapView.camera
            // Threshold guard: only nudge pitch on a meaningful delta so we don't re-enter
            // this callback in a feedback loop.
            guard abs(camera.pitch - target) > 0.5 else { return }
            camera.pitch = target
            mapView.setCamera(camera, animated: false)
        }

        func mapView(_ mapView: MLNMapView, didFailLoadingMapWithError error: Error) {
            Self.log.error("style load failed: \(error.localizedDescription, privacy: .public)")
        }

        private func resetOverlaySources() {
            zoneSource = nil
            mutedZoneSource = nil
            inRangeSource = nil
            inRangeFillLayer = nil
            inRangeRingLayer = nil
            heatmapSource = nil
            renderedZoneIDs = []
            renderedMutedZoneIDs = []
            renderedInRangeKey = ""
            renderedHeatmapPinIDs = []
            // Pin annotations are map-level (not style-level) — they survive a style
            // reload, so their diff state must NOT be reset here or the next sync
            // would double-add every pin.
            stopPulse()
        }

        private func applyStoredOverlayState(on mapView: MLNMapView) {
            syncZoneGlows(latestZoneGlows, on: mapView)
            syncMutedZones(latestMutedZones, on: mapView)
            syncInRangeHalos(ownPins: latestOwnPins, on: mapView)
            syncPins(own: latestOwnPins, revealed: latestRevealedPins, on: mapView)
        }

        // MARK: Zone glows

        private func ensureZoneLayer(on style: MLNStyle) {
            if let existing = style.source(withIdentifier: Self.zoneSourceID) as? MLNShapeSource {
                zoneSource = existing
                return
            }
            let source = MLNShapeSource(identifier: Self.zoneSourceID, shape: nil, options: nil)
            style.addSource(source)
            zoneSource = source

            guard style.layer(withIdentifier: Self.zoneFillLayerID) == nil else { return }
            let fill = MLNFillStyleLayer(identifier: Self.zoneFillLayerID, source: source)
            fill.fillColor = NSExpression(forConstantValue: UIColor(LegacyColor.accent))
            fill.fillOpacity = NSExpression(forKeyPath: "opacity")
            style.addLayer(fill)
        }

        func syncZoneGlows(_ glows: [ZoneGlowOverlay], on mapView: MLNMapView) {
            latestZoneGlows = glows
            let ids = glows.map(\.id)
            guard ids != renderedZoneIDs, let source = zoneSource else { return }
            renderedZoneIDs = ids
            let polygons: [MLNPolygonFeature] = glows.map { glow in
                let center = CLLocationCoordinate2D(latitude: glow.centerLat, longitude: glow.centerLng)
                var ring = Self.geodesicCircle(center: center, radiusMeters: glow.radiusMeters)
                let polygon = MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
                polygon.attributes = ["opacity": glow.opacity]
                return polygon
            }
            source.shape = MLNShapeCollectionFeature(shapes: polygons)
        }

        // MARK: Muted zones (user-defined notification silences — red overlays)

        private func ensureMutedZoneLayer(on style: MLNStyle) {
            if let existing = style.source(withIdentifier: Self.mutedZoneSourceID) as? MLNShapeSource {
                mutedZoneSource = existing
                return
            }
            let source = MLNShapeSource(identifier: Self.mutedZoneSourceID, shape: nil, options: nil)
            style.addSource(source)
            mutedZoneSource = source

            guard style.layer(withIdentifier: Self.mutedZoneFillLayerID) == nil else { return }
            let fill = MLNFillStyleLayer(identifier: Self.mutedZoneFillLayerID, source: source)
            fill.fillColor = NSExpression(forConstantValue: UIColor(LegacyColor.danger))
            fill.fillOpacity = NSExpression(forConstantValue: 0.18)
            fill.fillOutlineColor = NSExpression(
                forConstantValue: UIColor(LegacyColor.danger).withAlphaComponent(0.7)
            )
            style.addLayer(fill)
        }

        func syncMutedZones(_ zones: [MutedZone], on mapView: MLNMapView) {
            latestMutedZones = zones
            let ids = zones.map(\.id)
            guard ids != renderedMutedZoneIDs, let source = mutedZoneSource else { return }
            renderedMutedZoneIDs = ids
            let polygons: [MLNPolygonFeature] = zones.map { zone in
                let center = CLLocationCoordinate2D(latitude: zone.lat, longitude: zone.lng)
                var ring = Self.geodesicCircle(center: center, radiusMeters: CLLocationDistance(zone.radiusM))
                let polygon = MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
                return polygon
            }
            source.shape = MLNShapeCollectionFeature(shapes: polygons)
        }

        // MARK: In-range halos (visible even when the pin sits under the user puck)

        private func ensureInRangeLayer(on style: MLNStyle) {
            // Source — capture existing or create fresh.
            if let existing = style.source(withIdentifier: Self.inRangeSourceID) as? MLNShapeSource {
                inRangeSource = existing
            } else {
                let source = MLNShapeSource(identifier: Self.inRangeSourceID, shape: nil, options: nil)
                style.addSource(source)
                inRangeSource = source
            }

            // Fill layer — capture existing or create fresh. Opacity is set per-frame by
            // `tickInRangePulse` directly on the layer, so no per-feature attribute needed.
            if let existing = style.layer(withIdentifier: Self.inRangeFillLayerID) as? MLNFillStyleLayer {
                inRangeFillLayer = existing
            } else if let source = inRangeSource {
                let fill = MLNFillStyleLayer(identifier: Self.inRangeFillLayerID, source: source)
                fill.fillColor = NSExpression(forConstantValue: UIColor(LegacyColor.accent))
                fill.fillOpacity = NSExpression(forConstantValue: 0.28)
                style.addLayer(fill)
                inRangeFillLayer = fill
            }

            // Ring layer — crisp catchment-edge ring; opacity also driven by the pulse tick.
            if let existing = style.layer(withIdentifier: Self.inRangeRingLayerID) as? MLNLineStyleLayer {
                inRangeRingLayer = existing
            } else if let source = inRangeSource {
                let ring = MLNLineStyleLayer(identifier: Self.inRangeRingLayerID, source: source)
                ring.lineColor = NSExpression(forConstantValue: UIColor(LegacyColor.accent))
                ring.lineWidth = NSExpression(forConstantValue: 2.5)
                ring.lineOpacity = NSExpression(forConstantValue: 0.7)
                ring.lineCap = NSExpression(forConstantValue: "round")
                style.addLayer(ring)
                inRangeRingLayer = ring
            }
        }

        func syncInRangeHalos(ownPins: [CachedOwnPin], on mapView: MLNMapView) {
            latestOwnPins = ownPins
            let inRangeOwn = ownPins.filter { inRangeMemoryIDs.contains($0.memoryID) }
            let key = inRangeOwn.map(\.memoryID).sorted().joined(separator: ",")
            guard key != renderedInRangeKey, let source = inRangeSource else { return }
            renderedInRangeKey = key

            let polygons: [MLNPolygonFeature] = inRangeOwn.map { pin in
                let center = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
                var ring = Self.geodesicCircle(center: center, radiusMeters: Self.inRangeHaloRadiusMeters)
                // No per-feature opacity attributes — pulse tick drives the layer property
                // directly (O(1) vs O(n) shape-collection rebuild every 60 ms).
                return MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
            }
            source.shape = MLNShapeCollectionFeature(shapes: polygons)

            if polygons.isEmpty {
                stopPulse()
            } else {
                startPulseIfNeeded()
            }
        }

        private func startPulseIfNeeded() {
            guard pulseTimer == nil else { return }
            // Reduce Motion: hold the halo at a steady mid-brightness instead of breathing.
            guard !LegacyMotion.isReduced else {
                inRangeFillLayer?.fillOpacity = NSExpression(forConstantValue: 0.28)
                inRangeRingLayer?.lineOpacity = NSExpression(forConstantValue: 0.7)
                return
            }
            let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.tickInRangePulse()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            pulseTimer = timer
        }

        private func tickInRangePulse() {
            pulsePhase += 0.07
            let wave = 0.5 + 0.5 * sin(pulsePhase)
            // Write directly to the live style layer — one property assignment per tick
            // instead of rebuilding and re-uploading the entire GeoJSON shape collection.
            inRangeFillLayer?.fillOpacity = NSExpression(
                forConstantValue: Float(0.18 + 0.22 * wave)
            )
            inRangeRingLayer?.lineOpacity = NSExpression(
                forConstantValue: Float(0.55 + 0.30 * wave)
            )
        }

        // MARK: Density heatmap

        /// Heatmap layer visible only when zoomed out — the "your life, from above" view.
        /// Uses all own pins (not just in-range) so the full personal density is always visible.
        /// Fades to invisible at street zoom where individual pins take over.
        private func ensureHeatmapLayer(on style: MLNStyle) {
            if let existing = style.source(withIdentifier: Self.heatmapSourceID) as? MLNShapeSource {
                heatmapSource = existing
                return
            }
            let source = MLNShapeSource(identifier: Self.heatmapSourceID, shape: nil, options: nil)
            style.addSource(source)
            heatmapSource = source

            guard style.layer(withIdentifier: Self.heatmapLayerID) == nil else { return }
            let layer = MLNHeatmapStyleLayer(identifier: Self.heatmapLayerID, source: source)

            // Warm amber palette — continuous with the memory beacon hue so the density
            // cloud reads as "memories, concentrated here."
            layer.heatmapColor = NSExpression(
                forMLNInterpolating: NSExpression(forKeyPath: "$heatmapDensity"),
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    0.0 as NSNumber: UIColor.clear,
                    0.3 as NSNumber: UIColor(red: 0.95, green: 0.65, blue: 0.20, alpha: 0.0),
                    0.6 as NSNumber: UIColor(red: 0.95, green: 0.60, blue: 0.15, alpha: 0.55),
                    1.0 as NSNumber: UIColor(red: 0.95, green: 0.45, blue: 0.10, alpha: 0.85),
                ])
            )

            // Generous pixel radius — sparse pins still form coherent blobs.
            layer.heatmapRadius = NSExpression(
                forMLNInterpolating: NSExpression(forKeyPath: "$zoomLevel"),
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    10.0 as NSNumber: 20.0 as NSNumber,
                    14.0 as NSNumber: 70.0 as NSNumber,
                ])
            )

            // Fade out as street zoom approaches — pins take over the narrative.
            layer.heatmapOpacity = NSExpression(
                forMLNInterpolating: NSExpression(forKeyPath: "$zoomLevel"),
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    WanderMapStyle.flatPitchZoom as NSNumber: 0.80 as NSNumber,
                    WanderMapStyle.fullPitchZoom as NSNumber: 0.0 as NSNumber,
                ])
            )

            style.addLayer(layer)
        }

        func syncHeatmap(ownPins: [CachedOwnPin], on mapView: MLNMapView) {
            let ids = ownPins.map(\.memoryID).sorted()
            guard ids != renderedHeatmapPinIDs, let source = heatmapSource else { return }
            renderedHeatmapPinIDs = ids
            let features: [MLNPointFeature] = ownPins.map { pin in
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
                return f
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }

        // MARK: Memory pins

        /// Wire format is ISO 8601 full-date ("2024-09-01"); date-time kept as fallback.
        /// ISO8601DateFormatter is thread-safe, so shared statics are fine.
        private static let fullDateParser: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withFullDate]
            return f
        }()
        private static let dateTimeParser = ISO8601DateFormatter()

        /// Parse a drop-date string and return elapsed years.
        private static func pinAgeYears(from dropDate: String) -> Double {
            guard let d = fullDateParser.date(from: dropDate)
                ?? dateTimeParser.date(from: dropDate) else { return 0 }
            return max(0, -d.timeIntervalSinceNow) / (365.25 * 24 * 3600)
        }

        func syncPins(own: [CachedOwnPin], revealed: [RevealedMemoryPin], on mapView: MLNMapView) {
            latestOwnPins = own
            latestRevealedPins = revealed

            // Keep the heatmap in sync — same pin list, different visual.
            syncHeatmap(ownPins: own, on: mapView)

            var nextStates: [PinRenderState] = []
            nextStates.reserveCapacity(own.count + revealed.count)
            for pin in own {
                nextStates.append(
                    PinRenderState(
                        memoryID: pin.memoryID,
                        style: .own,
                        inRange: inRangeMemoryIDs.contains(pin.memoryID)
                    )
                )
            }
            for pin in revealed {
                nextStates.append(
                    PinRenderState(
                        memoryID: pin.memoryID,
                        style: .revealed,
                        inRange: inRangeMemoryIDs.contains(pin.memoryID)
                    )
                )
            }
            guard nextStates != renderedPinStates else { return }
            renderedPinStates = nextStates

            // Diff against live annotations: remove stale, add new, restyle changed
            // in place. One pin stepping in/out of range no longer rebuilds the map.
            struct DesiredPin {
                let style: PinAnnotation.Style
                let inRange: Bool
                let coordinate: CLLocationCoordinate2D
                let ageYears: Double
                let title: String
            }
            var desired: [String: DesiredPin] = [:]
            desired.reserveCapacity(own.count + revealed.count)
            for pin in own {
                desired[pin.memoryID] = DesiredPin(
                    style: .own,
                    inRange: inRangeMemoryIDs.contains(pin.memoryID),
                    coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng),
                    ageYears: Self.pinAgeYears(from: pin.dropDate),
                    title: "Your memory"
                )
            }
            for pin in revealed where desired[pin.memoryID] == nil {
                desired[pin.memoryID] = DesiredPin(
                    style: .revealed,
                    inRange: inRangeMemoryIDs.contains(pin.memoryID),
                    coordinate: CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng),
                    ageYears: 0,  // revealed pins carry no drop-date client-side
                    title: "Memory nearby"
                )
            }

            let staleIDs = pinAnnotationsByID.keys.filter { desired[$0] == nil }
            if !staleIDs.isEmpty {
                let stale = staleIDs.compactMap { pinAnnotationsByID.removeValue(forKey: $0) }
                mapView.removeAnnotations(stale)
            }

            var additions: [PinAnnotation] = []
            for (memoryID, want) in desired {
                if let existing = pinAnnotationsByID[memoryID] {
                    if existing.coordinate.latitude != want.coordinate.latitude
                        || existing.coordinate.longitude != want.coordinate.longitude {
                        existing.coordinate = want.coordinate
                    }
                    if existing.inRange != want.inRange {
                        existing.inRange = want.inRange
                        if let view = mapView.view(for: existing) as? LegacyPinAnnotationView {
                            view.configure(
                                style: existing.style,
                                inRange: want.inRange,
                                ageYears: existing.ageYears
                            )
                            view.syncInRangePulse(active: want.inRange)
                        }
                    }
                } else {
                    let annotation = PinAnnotation(
                        memoryID: memoryID,
                        style: want.style,
                        inRange: want.inRange,
                        ageYears: want.ageYears,
                        shouldAnimateDrop: true
                    )
                    annotation.coordinate = want.coordinate
                    annotation.title = want.title
                    pinAnnotationsByID[memoryID] = annotation
                    additions.append(annotation)
                }
            }
            if !additions.isEmpty {
                mapView.addAnnotations(additions)
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if annotation is MLNUserLocation {
                if let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.userPuckReuseID) as? LegacyUserPuckView {
                    return view
                }
                return LegacyUserPuckView(reuseIdentifier: Self.userPuckReuseID)
            }
            guard let pin = annotation as? PinAnnotation else { return nil }
            let reuseID = pin.style == .own ? Self.ownReuseID : Self.revealedReuseID
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseID) as? LegacyPinAnnotationView
                ?? LegacyPinAnnotationView(reuseIdentifier: reuseID)
            view.configure(style: pin.style, inRange: pin.inRange, ageYears: pin.ageYears)
            if pin.shouldAnimateDrop {
                view.playDropAnimation()
                pin.shouldAnimateDrop = false
            } else {
                view.syncInRangePulse(active: pin.inRange)
            }
            return view
        }

        // MARK: Marker rendering

        private static func geodesicCircle(
            center: CLLocationCoordinate2D,
            radiusMeters: Double,
            steps: Int = 64
        ) -> [CLLocationCoordinate2D] {
            let earthRadius = 6_378_137.0
            let latRad = center.latitude * .pi / 180
            var coords: [CLLocationCoordinate2D] = []
            coords.reserveCapacity(steps + 1)
            for i in 0...steps {
                let theta = Double(i) / Double(steps) * 2 * .pi
                let dx = radiusMeters * cos(theta)
                let dy = radiusMeters * sin(theta)
                let dLat = (dy / earthRadius) * 180 / .pi
                let dLng = (dx / (earthRadius * cos(latRad))) * 180 / .pi
                coords.append(
                    CLLocationCoordinate2D(
                        latitude: center.latitude + dLat,
                        longitude: center.longitude + dLng
                    )
                )
            }
            return coords
        }
    }
}

/// Point annotation that remembers which visual style to render.
private final class PinAnnotation: MLNPointAnnotation {
    enum Style { case own, revealed }
    let memoryID: String
    let style: Style
    var inRange: Bool
    let ageYears: Double
    var shouldAnimateDrop: Bool

    init(memoryID: String, style: Style, inRange: Bool, ageYears: Double, shouldAnimateDrop: Bool) {
        self.memoryID = memoryID
        self.style = style
        self.inRange = inRange
        self.ageYears = ageYears
        self.shouldAnimateDrop = shouldAnimateDrop
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Animated map pin — warm beacon aesthetic; drop on first appearance, pulse when in range.
private final class LegacyPinAnnotationView: MLNAnnotationView {
    private let imageView = UIImageView()
    private var pulseAnimationKey = "legacy.pin.pulse"
    private var isInRange = false

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 52, height: 58)
        centerOffset = CGVector(dx: 0, dy: -22)
        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }

    func configure(style: PinAnnotation.Style, inRange: Bool, ageYears: Double) {
        self.isInRange = inRange
        imageView.image = LegacyMemoryPinArt.image(style: style, inRange: inRange, ageYears: ageYears)
    }

    func playDropAnimation() {
        layer.removeAnimation(forKey: pulseAnimationKey)
        transform = CGAffineTransform(translationX: 0, y: -32).scaledBy(x: 0.08, y: 0.08)
        alpha = 0
        UIView.animate(
            withDuration: 0.52,
            delay: 0,
            usingSpringWithDamping: 0.58,
            initialSpringVelocity: 0.9,
            options: [.allowUserInteraction]
        ) {
            self.transform = .identity
            self.alpha = 1
        } completion: { _ in
            self.syncInRangePulse(active: self.isInRange)
        }
    }

    func syncInRangePulse(active: Bool) {
        layer.removeAnimation(forKey: pulseAnimationKey)
        guard active, !LegacyMotion.isReduced else {
            transform = .identity
            return
        }
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.14
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: pulseAnimationKey)
    }
}

/// Map view that keeps the user's focal point low on screen via a top content inset,
/// so the world scrolls *ahead* of the avatar (PoGo-style first-person framing).
private final class OffsetMLNMapView: MLNMapView {
    var verticalBias: CGFloat = 0.42
    private var appliedTopInset: CGFloat = -1

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = bounds.height
        guard height > 0 else { return }
        let topInset = (height * verticalBias).rounded()
        guard abs(appliedTopInset - topInset) > 0.5 else { return }
        appliedTopInset = topInset
        setContentInset(UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0), animated: false)
    }
}

private final class LegacyUserPuckView: MLNUserLocationAnnotationView {
    private let imageView = UIImageView()
    private let puckSize = CGSize(width: 60, height: 68)
    /// Orb sits below the canvas centre (cone needs headroom above) — shift the view
    /// up so the orb, not the cone tip, lands on the actual coordinate.
    private let orbCenterYRatio: CGFloat = 0.66
    private var displayLink: CADisplayLink?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        // Fixed screen size — never grow/shrink with zoom or the tilted camera.
        scalesWithViewingDistance = false

        bounds = CGRect(origin: .zero, size: puckSize)
        let orbOffset = puckSize.height * (orbCenterYRatio - 0.5)
        centerOffset = CGVector(dx: 0, dy: -orbOffset)

        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.image = LegacyUserPuckArt.image(size: puckSize, orbCenterYRatio: orbCenterYRatio)
        addSubview(imageView)

        startTransformGuard()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func update() {
        // Keep a non-null frame so MapLibre positions the puck; artwork is built in init.
        if frame.isNull {
            frame = CGRect(origin: .zero, size: puckSize)
        }
        scalesWithViewingDistance = false
        assertIdentityTransform()
    }

    private func startTransformGuard() {
        displayLink = CADisplayLink(
            target: self,
            selector: #selector(assertIdentityTransform)
        )
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func assertIdentityTransform() {
        scalesWithViewingDistance = false
        if !CATransform3DIsIdentity(layer.transform) {
            layer.transform = CATransform3DIdentity
        }
    }

    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
}

/// Premium location puck — gradient orb with a warm heading cone fanning forward.
/// Because the Wander map heading-locks, "up" is always forward, so the cone is static.
private enum LegacyUserPuckArt {
    static func image(size: CGSize, orbCenterYRatio: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            // Cool location-blue, deliberately OFF the warm accent palette: memory
            // beacons are amber orbs, so the user puck must not share their hue or it
            // reads as just another memory. Blue is also the universal "you are here."
            let accent = UIColor(red: 0.34, green: 0.66, blue: 1.0, alpha: 1)
            let accentDeep = UIColor(red: 0.13, green: 0.40, blue: 0.92, alpha: 1)
            let rgb = CGColorSpaceCreateDeviceRGB()
            let orbCenter = CGPoint(x: size.width / 2, y: size.height * orbCenterYRatio)
            let orbRadius: CGFloat = 10

            // ── Heading cone — warm light fanning forward (up), fading to nothing ──
            let coneTopY: CGFloat = 8
            let coneHalfWidth: CGFloat = 19
            let cone = CGMutablePath()
            cone.move(to: orbCenter)
            cone.addLine(to: CGPoint(x: orbCenter.x - coneHalfWidth, y: coneTopY))
            cone.addQuadCurve(
                to: CGPoint(x: orbCenter.x + coneHalfWidth, y: coneTopY),
                control: CGPoint(x: orbCenter.x, y: coneTopY - 5)
            )
            cone.closeSubpath()
            cg.saveGState()
            cg.addPath(cone)
            cg.clip()
            if let grad = CGGradient(
                colorsSpace: rgb,
                colors: [
                    accent.withAlphaComponent(0).cgColor,
                    accent.withAlphaComponent(0.42).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    grad,
                    start: CGPoint(x: orbCenter.x, y: coneTopY),
                    end: orbCenter,
                    options: []
                )
            }
            cg.restoreGState()

            // ── Outer bloom behind the orb ──
            cg.setShadow(offset: .zero, blur: 12, color: accent.withAlphaComponent(0.6).cgColor)
            cg.setFillColor(accent.withAlphaComponent(0.22).cgColor)
            cg.fillEllipse(in: CGRect(
                x: orbCenter.x - orbRadius - 4, y: orbCenter.y - orbRadius - 4,
                width: (orbRadius + 4) * 2, height: (orbRadius + 4) * 2
            ))
            cg.setShadow(offset: .zero, blur: 0, color: nil)

            // ── Orb body — radial gradient with an off-centre highlight ──
            let orbRect = CGRect(
                x: orbCenter.x - orbRadius, y: orbCenter.y - orbRadius,
                width: orbRadius * 2, height: orbRadius * 2
            )
            cg.setShadow(
                offset: CGSize(width: 0, height: 2),
                blur: 4,
                color: UIColor.black.withAlphaComponent(0.4).cgColor
            )
            if let grad = CGGradient(
                colorsSpace: rgb,
                colors: [accent.cgColor, accentDeep.cgColor] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawRadialGradient(
                    grad,
                    startCenter: CGPoint(x: orbCenter.x - 3, y: orbCenter.y - 4),
                    startRadius: 1,
                    endCenter: orbCenter,
                    endRadius: orbRadius,
                    options: []
                )
            }
            cg.setShadow(offset: .zero, blur: 0, color: nil)

            // ── Crisp white ring ──
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
            cg.setLineWidth(2)
            cg.strokeEllipse(in: orbRect.insetBy(dx: 1, dy: 1))
        }
    }
}

/// Custom pin artwork — warm beacon orbs instead of stock SF Symbol map pins.
private enum LegacyMemoryPinArt {
    static func image(style: PinAnnotation.Style, inRange: Bool, ageYears: Double) -> UIImage {
        let size = CGSize(width: 52, height: 58)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let accent = UIColor(LegacyColor.accent)
            let accentDeep = UIColor(LegacyColor.accentDeep)
            let center = CGPoint(x: size.width / 2, y: 22)
            let orbRadius: CGFloat = inRange ? 15 : (style == .own ? 13 : 11)

            // Patina: own pins fade gently with age — a faded-photograph aesthetic.
            // In-range and others' pins are always fully saturated.
            let patina = min(ageYears / 3.0, 1.0)
            let pinAlpha: CGFloat = (style == .own && !inRange) ? max(0.68, 1.0 - patina * 0.32) : 1.0

            if inRange {
                ctx.cgContext.setShadow(
                    offset: .zero,
                    blur: 14,
                    color: accent.withAlphaComponent(0.55).cgColor
                )
                ctx.cgContext.setFillColor(accent.withAlphaComponent(0.28).cgColor)
                ctx.cgContext.fillEllipse(in: CGRect(
                    x: center.x - orbRadius - 6,
                    y: center.y - orbRadius - 6,
                    width: (orbRadius + 6) * 2,
                    height: (orbRadius + 6) * 2
                ))
                ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            }

            ctx.cgContext.setShadow(
                offset: CGSize(width: 0, height: 3),
                blur: 5,
                color: UIColor.black.withAlphaComponent(0.45).cgColor
            )
            let orbRect = CGRect(
                x: center.x - orbRadius,
                y: center.y - orbRadius,
                width: orbRadius * 2,
                height: orbRadius * 2
            )
            let colors: [CGColor]
            if inRange {
                colors = [accent.cgColor, accentDeep.cgColor]
            } else if style == .own {
                colors = [
                    accent.withAlphaComponent(pinAlpha).cgColor,
                    accentDeep.withAlphaComponent(pinAlpha * 0.9).cgColor,
                ]
            } else {
                colors = [
                    accent.withAlphaComponent(0.75).cgColor,
                    accentDeep.withAlphaComponent(0.65).cgColor,
                ]
            }
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            ) {
                ctx.cgContext.drawRadialGradient(
                    gradient,
                    startCenter: CGPoint(x: orbRect.midX - 3, y: orbRect.midY - 4),
                    startRadius: 1,
                    endCenter: center,
                    endRadius: orbRadius,
                    options: []
                )
            }
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

            ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.85 * pinAlpha).cgColor)
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokeEllipse(in: orbRect.insetBy(dx: 0.5, dy: 0.5))

            let symbolName = inRange ? "sparkle" : (style == .own ? "heart.fill" : "photo.fill")
            let symbolSize: CGFloat = inRange ? 13 : (style == .own ? 11 : 9)
            let config = UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
            if let symbol = UIImage(systemName: symbolName, withConfiguration: config)?
                .withTintColor(
                    UIColor(LegacyColor.textOnAccent).withAlphaComponent(pinAlpha),
                    renderingMode: .alwaysOriginal
                ) {
                symbol.draw(at: CGPoint(
                    x: center.x - symbol.size.width / 2,
                    y: center.y - symbol.size.height / 2
                ))
            }

            // Ground anchor — ties the orb to the map surface.
            ctx.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.35 * pinAlpha).cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: center.x - 4, y: center.y + orbRadius + 2, width: 8, height: 3))
        }
    }
}

enum WanderMapStyle {
    /// Fiord base — cool dark OSM canvas we warm-tint at load time.
    static let current = URL(string: "https://tiles.openfreemap.org/styles/fiord")!
    static let pitch: CGFloat = 58
    static let streetZoom: Double = 16.8
    static let userScreenBias: CGFloat = 0.40

    /// Camera tilt as a function of zoom. The immersive 58° tilt holds at street level,
    /// then ramps to a flat top-down view as you pull out. Rationale: at a steep pitch,
    /// a zoomed-out coordinate projects up near the horizon where tiny camera deltas swing
    /// its screen position wildly — that's what makes the user puck "swim"/glitch on
    /// zoom-out. Flattening the camera removes the perspective foreshortening entirely, so
    /// the puck stays pinned. (Also how Google Maps / PoGo behave at region scale.)
    static let fullPitchZoom: Double = 15.0
    static let flatPitchZoom: Double = 12.5

    static func pitch(forZoom zoom: Double) -> CGFloat {
        if zoom >= fullPitchZoom { return pitch }
        if zoom <= flatPitchZoom { return 0 }
        let t = (zoom - flatPitchZoom) / (fullPitchZoom - flatPitchZoom)
        // Smoothstep — eases in/out at both ends so the tilt doesn't snap on or off as you
        // cross the band, which reads smoother than a raw linear ramp.
        let eased = t * t * (3 - 2 * t)
        return pitch * CGFloat(eased)
    }

    /// Retheme the stock vector style toward Legacy's warm, memory-atlas palette.
    /// Canvas and water shift subtly with the time of day: dawn is blue-cool, golden hour
    /// leans amber, night is the default deep dark.
    static func applyLegacyTheme(to style: MLNStyle) {
        let hour = Calendar.current.component(.hour, from: Date())
        let (canvas, water) = timeOfDayCanvas(hour: hour)
        let building = UIColor(red: 0.14, green: 0.11, blue: 0.16, alpha: 0.72)
        let roadWarm = UIColor(red: 0.15, green: 0.13, blue: 0.18, alpha: 0.60)
        let roadMajor = UIColor(red: 0.21, green: 0.19, blue: 0.24, alpha: 0.75)
        let park = UIColor(red: 0.10, green: 0.14, blue: 0.11, alpha: 0.55)

        if let layer = style.layer(withIdentifier: "background") as? MLNBackgroundStyleLayer {
            layer.backgroundColor = NSExpression(forConstantValue: canvas)
        }
        setFillColor(water, on: style, layerIDs: ["water"])
        setFillColor(building, on: style, layerIDs: ["building"])
        setFillColor(park, on: style, layerIDs: ["park", "landcover_wood"])
        setLineColor(roadWarm, on: style, layerIDs: ["highway_minor", "highway_path"])
        setLineColor(roadMajor, on: style, layerIDs: [
            "highway_major_inner",
            "highway_motorway_inner",
            "highway_major_subtle",
            "highway_motorway_subtle",
        ])

        // Less label clutter — keep major place names, drop refs and minor labels.
        let hiddenLayers = [
            "water_name",
            "highway_name_other",
            "highway_ref",
            "place_other",
            "place_suburb",
            "place_village",
            "aeroway-taxiway",
            "aeroway-runway-casing",
            "aeroway-runway",
            "aeroway-area",
            "railway_transit",
            "railway_transit_dashline",
            "railway_service",
            "railway_service_dashline",
            "railway",
            "railway_dashline",
        ]
        for id in hiddenLayers {
            style.layer(withIdentifier: id)?.isVisible = false
        }

        addBuildingExtrusions(to: style)
    }

    /// Canvas (map background) and water colors keyed by hour of day.
    private static func timeOfDayCanvas(hour: Int) -> (canvas: UIColor, water: UIColor) {
        switch hour {
        case 5..<8:   // pre-dawn / dawn — cool blue tint
            return (UIColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1),
                    UIColor(red: 0.08, green: 0.09, blue: 0.15, alpha: 1))
        case 8..<17:  // day — slightly lighter, more neutral
            return (UIColor(red: 0.09, green: 0.08, blue: 0.11, alpha: 1),
                    UIColor(red: 0.11, green: 0.10, blue: 0.14, alpha: 1))
        case 17..<21: // golden hour / dusk — amber warmth
            return (UIColor(red: 0.10, green: 0.07, blue: 0.07, alpha: 1),
                    UIColor(red: 0.12, green: 0.08, blue: 0.10, alpha: 1))
        default:      // night (21–5) — deep cool dark (base palette)
            return (UIColor(red: 0.07, green: 0.06, blue: 0.09, alpha: 1),
                    UIColor(red: 0.09, green: 0.08, blue: 0.13, alpha: 1))
        }
    }

    /// Adds 3D building extrusions using OpenMapTiles render_height data.
    /// Fades in above zoom 14 where the 58° pitch makes depth meaningful.
    /// Falls back gracefully if the building layer or vector source isn't in the style.
    private static func addBuildingExtrusions(to style: MLNStyle) {
        let layerID = "legacy.building.extrusion"
        guard style.layer(withIdentifier: layerID) == nil,
              let buildingFill = style.layer(withIdentifier: "building") as? MLNFillStyleLayer,
              let sourceID = buildingFill.sourceIdentifier,
              let vectorSource = style.source(withIdentifier: sourceID)
        else { return }

        let extrusion = MLNFillExtrusionStyleLayer(identifier: layerID, source: vectorSource)
        extrusion.sourceLayerIdentifier = buildingFill.sourceLayerIdentifier ?? "building"

        // Slightly lighter than the flat building fill so faces catch implied light.
        extrusion.fillExtrusionColor = NSExpression(
            forConstantValue: UIColor(red: 0.18, green: 0.15, blue: 0.22, alpha: 1)
        )

        // OpenMapTiles schema: render_height / render_min_height. Default to 4 m flat roof.
        extrusion.fillExtrusionHeight = NSExpression(
            forConditional: NSPredicate(format: "render_height != nil"),
            trueExpression: NSExpression(forKeyPath: "render_height"),
            falseExpression: NSExpression(forConstantValue: 4.0)
        )
        extrusion.fillExtrusionBase = NSExpression(
            forConditional: NSPredicate(format: "render_min_height != nil"),
            trueExpression: NSExpression(forKeyPath: "render_min_height"),
            falseExpression: NSExpression(forConstantValue: 0.0)
        )

        // Fade in at street zoom — invisible at region scale where pitch is flat anyway.
        extrusion.fillExtrusionOpacity = NSExpression(
            forMLNInterpolating: NSExpression(forKeyPath: "$zoomLevel"),
            curveType: .linear,
            parameters: nil,
            stops: NSExpression(forConstantValue: [
                14.0 as NSNumber: 0.0 as NSNumber,
                15.5 as NSNumber: 0.65 as NSNumber,
            ])
        )

        style.insertLayer(extrusion, above: buildingFill)
    }

    private static func setFillColor(_ color: UIColor, on style: MLNStyle, layerIDs: [String]) {
        for id in layerIDs {
            guard let layer = style.layer(withIdentifier: id) as? MLNFillStyleLayer else { continue }
            layer.fillColor = NSExpression(forConstantValue: color)
        }
    }

    private static func setLineColor(_ color: UIColor, on style: MLNStyle, layerIDs: [String]) {
        for id in layerIDs {
            guard let layer = style.layer(withIdentifier: id) as? MLNLineStyleLayer else { continue }
            layer.lineColor = NSExpression(forConstantValue: color)
        }
    }
}
#endif
