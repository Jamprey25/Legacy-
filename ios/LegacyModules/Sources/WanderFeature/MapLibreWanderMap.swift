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
        private var relockTimer: Timer?
        private var lastInteractionTime: CFTimeInterval = 0
        private static let relockAfterIdle: TimeInterval = 6

        private var zoneSource: MLNShapeSource?
        private var mutedZoneSource: MLNShapeSource?
        private var inRangeSource: MLNShapeSource?
        private var renderedZoneIDs: [String] = []
        private var renderedMutedZoneIDs: [String] = []
        private var renderedInRangeKey = ""
        private var renderedPinStates: [PinRenderState] = []
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
            renderedZoneIDs = []
            renderedMutedZoneIDs = []
            renderedInRangeKey = ""
            renderedPinStates = []
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
            if let existing = style.source(withIdentifier: Self.inRangeSourceID) as? MLNShapeSource {
                inRangeSource = existing
                return
            }
            let source = MLNShapeSource(identifier: Self.inRangeSourceID, shape: nil, options: nil)
            style.addSource(source)
            inRangeSource = source

            guard style.layer(withIdentifier: Self.inRangeFillLayerID) == nil else { return }
            let fill = MLNFillStyleLayer(identifier: Self.inRangeFillLayerID, source: source)
            fill.fillColor = NSExpression(forConstantValue: UIColor(LegacyColor.accent))
            fill.fillOpacity = NSExpression(forKeyPath: "opacity")
            style.addLayer(fill)

            // Crisp pulsing ring at the catchment edge — the PoGo "you've stepped into
            // range" bloom. Drawn on the same source so it tracks the soft glow's circle.
            let ring = MLNLineStyleLayer(identifier: Self.inRangeRingLayerID, source: source)
            ring.lineColor = NSExpression(forConstantValue: UIColor(LegacyColor.accent))
            ring.lineWidth = NSExpression(forConstantValue: 2.5)
            ring.lineOpacity = NSExpression(forKeyPath: "ringOpacity")
            ring.lineCap = NSExpression(forConstantValue: "round")
            style.addLayer(ring)
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
                let polygon = MLNPolygonFeature(coordinates: &ring, count: UInt(ring.count))
                polygon.attributes = ["opacity": 0.34, "ringOpacity": 0.7]
                return polygon
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
            let opacity = 0.18 + 0.22 * wave        // soft interior glow
            let ringOpacity = 0.55 + 0.30 * wave    // crisp catchment ring, breathes brighter
            guard let source = inRangeSource,
                  let collection = source.shape as? MLNShapeCollectionFeature else { return }
            for case let polygon as MLNPolygonFeature in collection.shapes ?? [] {
                polygon.attributes = ["opacity": opacity, "ringOpacity": ringOpacity]
            }
            source.shape = collection
        }

        // MARK: Memory pins

        func syncPins(own: [CachedOwnPin], revealed: [RevealedMemoryPin], on mapView: MLNMapView) {
            latestOwnPins = own
            latestRevealedPins = revealed
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

            let previousIDs = Set(renderedPinStates.map(\.memoryID))
            renderedPinStates = nextStates

            let existingPins = (mapView.annotations ?? []).compactMap { $0 as? PinAnnotation }
            mapView.removeAnnotations(existingPins)

            var annotations: [PinAnnotation] = []
            annotations.reserveCapacity(own.count + revealed.count)
            for pin in own {
                let annotation = PinAnnotation(
                    memoryID: pin.memoryID,
                    style: .own,
                    inRange: inRangeMemoryIDs.contains(pin.memoryID),
                    shouldAnimateDrop: !previousIDs.contains(pin.memoryID)
                )
                annotation.coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
                annotation.title = "Your memory"
                annotations.append(annotation)
            }
            for pin in revealed {
                let annotation = PinAnnotation(
                    memoryID: pin.memoryID,
                    style: .revealed,
                    inRange: inRangeMemoryIDs.contains(pin.memoryID),
                    shouldAnimateDrop: !previousIDs.contains(pin.memoryID)
                )
                annotation.coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
                annotation.title = "Memory nearby"
                annotations.append(annotation)
            }
            mapView.addAnnotations(annotations)
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
            view.configure(style: pin.style, inRange: pin.inRange)
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
    var shouldAnimateDrop: Bool

    init(memoryID: String, style: Style, inRange: Bool, shouldAnimateDrop: Bool) {
        self.memoryID = memoryID
        self.style = style
        self.inRange = inRange
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

    func configure(style: PinAnnotation.Style, inRange: Bool) {
        self.isInRange = inRange
        imageView.image = LegacyMemoryPinArt.image(style: style, inRange: inRange)
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
    static func image(style: PinAnnotation.Style, inRange: Bool) -> UIImage {
        let size = CGSize(width: 52, height: 58)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let accent = UIColor(LegacyColor.accent)
            let accentDeep = UIColor(LegacyColor.accentDeep)
            let center = CGPoint(x: size.width / 2, y: 22)
            let orbRadius: CGFloat = inRange ? 15 : (style == .own ? 13 : 11)

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
            let colors = style == .own || inRange
                ? [accent.cgColor, accentDeep.cgColor]
                : [accent.withAlphaComponent(0.75).cgColor, accentDeep.withAlphaComponent(0.65).cgColor]
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

            ctx.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.strokeEllipse(in: orbRect.insetBy(dx: 0.5, dy: 0.5))

            let symbolName = inRange ? "sparkle" : (style == .own ? "heart.fill" : "photo.fill")
            let symbolSize: CGFloat = inRange ? 13 : (style == .own ? 11 : 9)
            let config = UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
            if let symbol = UIImage(systemName: symbolName, withConfiguration: config)?
                .withTintColor(UIColor(LegacyColor.textOnAccent), renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(
                    x: center.x - symbol.size.width / 2,
                    y: center.y - symbol.size.height / 2
                ))
            }

            // Ground anchor — ties the orb to the map surface.
            ctx.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.35).cgColor)
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
    static func applyLegacyTheme(to style: MLNStyle) {
        let canvas = UIColor(red: 0.07, green: 0.06, blue: 0.09, alpha: 1)
        let water = UIColor(red: 0.09, green: 0.08, blue: 0.13, alpha: 1)
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
