#if os(iOS)
import APIClient
import CoreLocation
import DesignSystem
import LocationEngine
import MapLibre
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
        weak var mapView: MLNMapView?
        var pendingInitialPitch: CGFloat?
        var inRangeMemoryIDs: Set<String> = []
        var onTrackingLost: (() -> Void)?

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

        private struct PinRenderState: Equatable {
            let memoryID: String
            let style: PinAnnotation.Style
            let inRange: Bool
        }

        deinit {
            pulseTimer?.invalidate()
        }

        func stopPulse() {
            pulseTimer?.invalidate()
            pulseTimer = nil
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
            } else {
                // setUserTrackingMode resets pitch to 0 — restore it after every re-lock.
                let camera = mapView.camera
                guard camera.pitch < WanderMapStyle.pitch - 1 else { return }
                camera.pitch = WanderMapStyle.pitch
                mapView.setCamera(camera, withDuration: 0.35, animationTimingFunction: nil)
            }
        }

        func mapView(_ mapView: MLNMapView, didFailLoadingMapWithError error: Error) {
            print("[WanderMap] style load failed:", error.localizedDescription)
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
                polygon.attributes = ["opacity": 0.34]
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
            let opacity = 0.18 + 0.22 * (0.5 + 0.5 * sin(pulsePhase))
            guard let source = inRangeSource,
                  let collection = source.shape as? MLNShapeCollectionFeature else { return }
            for case let polygon as MLNPolygonFeature in collection.shapes ?? [] {
                polygon.attributes = ["opacity": opacity]
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
    private let puckSize = CGSize(width: 30, height: 36)
    private var built = false

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func update() {
        if frame.isNull {
            frame = CGRect(origin: .zero, size: puckSize)
            return setNeedsLayout()
        }
        guard !built else { return }
        built = true
        backgroundColor = .clear

        let accent = UIColor(LegacyColor.accent)
        let w = puckSize.width
        let h = puckSize.height
        let r: CGFloat = 5

        // Soft ambient bloom behind the arrow
        let bloom = CAShapeLayer()
        let bloomR: CGFloat = 12
        let cx = w / 2, cy = h * 0.6
        bloom.path = UIBezierPath(
            ovalIn: CGRect(x: cx - bloomR, y: cy - bloomR, width: bloomR * 2, height: bloomR * 2)
        ).cgPath
        bloom.fillColor = accent.withAlphaComponent(0.14).cgColor
        bloom.shadowColor = accent.cgColor
        bloom.shadowOpacity = 0.38
        bloom.shadowRadius = 12
        bloom.shadowOffset = .zero
        layer.addSublayer(bloom)

        // Chevron arrow with rounded bottom corners — top point stays sharp for direction
        let path = UIBezierPath()
        path.move(to: CGPoint(x: w / 2, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: h - r))
        path.addQuadCurve(
            to: CGPoint(x: w / 2 + r, y: h * 0.72),
            controlPoint: CGPoint(x: w, y: h)
        )
        path.addLine(to: CGPoint(x: w / 2, y: h * 0.68))
        path.addLine(to: CGPoint(x: w / 2 - r, y: h * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: r, y: h - r),
            controlPoint: CGPoint(x: 0, y: h)
        )
        path.close()

        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.fillColor = accent.cgColor
        shape.strokeColor = UIColor.white.withAlphaComponent(0.60).cgColor
        shape.lineWidth = 1.5
        shape.lineJoin = .round
        shape.shadowColor = accent.cgColor
        shape.shadowOpacity = 0.70
        shape.shadowRadius = 7
        shape.shadowOffset = .zero
        layer.addSublayer(shape)
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
