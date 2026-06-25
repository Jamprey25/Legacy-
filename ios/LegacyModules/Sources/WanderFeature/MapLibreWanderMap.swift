#if os(iOS)
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
/// tiles + styles, no API key, no signup, no billing. The style URL is the single knob
/// for the entire look — swap `WanderMapStyle.current` to retheme the whole map.
///
/// This view is intentionally a drop-in for `WanderUserMap` (same init signature) so the
/// swap at the call site is one line and trivially reversible.
struct MapLibreWanderMap: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let ownPins: [CachedOwnPin]
    let revealedOthersPins: [RevealedMemoryPin]
    let zoneGlows: [ZoneGlowOverlay]

    // MARK: UIViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: WanderMapStyle.current)
        mapView.delegate = context.coordinator
        context.coordinator.mapView = mapView

        // Immersive feel: pitched camera + map rotates to the user's heading so "forward"
        // is always up. This is the single biggest contributor to the in-world sensation.
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .followWithHeading
        mapView.setCenter(coordinate, zoomLevel: WanderMapStyle.streetZoom, animated: false)

        // Chrome we don't want competing with the memory pins.
        mapView.logoView.isHidden = false          // OpenFreeMap/OSM attribution must stay visible
        mapView.compassView.compassVisibility = .adaptive
        mapView.allowsRotating = true
        mapView.allowsTilting = true

        // Apply pitch once the style finishes loading (see delegate didFinishLoading).
        context.coordinator.pendingInitialPitch = WanderMapStyle.pitch
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.syncZoneGlows(zoneGlows, on: mapView)
        context.coordinator.syncPins(own: ownPins, revealed: revealedOthersPins, on: mapView)
    }

    static func dismantleUIView(_ mapView: MLNMapView, coordinator: Coordinator) {
        mapView.delegate = nil
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MLNMapViewDelegate {
        weak var mapView: MLNMapView?
        var pendingInitialPitch: CGFloat?

        private var zoneSource: MLNShapeSource?
        private var renderedZoneIDs: [String] = []
        private var renderedOwnIDs: [String] = []
        private var renderedRevealedIDs: [String] = []

        private static let ownReuseID = "legacy.pin.own"
        private static let revealedReuseID = "legacy.pin.revealed"

        // MARK: Style lifecycle

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            // Tilt into the world once tiles are ready.
            if let pitch = pendingInitialPitch {
                let camera = mapView.camera
                camera.pitch = pitch
                mapView.setCamera(camera, animated: false)
                pendingInitialPitch = nil
            }
            installZoneLayer(on: style)
        }

        // MARK: Zone glows (precision-7 coarse zones rendered as soft geodesic discs)

        private func installZoneLayer(on style: MLNStyle) {
            let source = MLNShapeSource(identifier: "legacy.zones", shape: nil, options: nil)
            style.addSource(source)
            zoneSource = source

            let fill = MLNFillStyleLayer(identifier: "legacy.zones.fill", source: source)
            fill.fillColor = NSExpression(forConstantValue: UIColor(LegacyColor.accent))
            // Per-feature opacity carried on the polygon's `opacity` attribute.
            fill.fillOpacity = NSExpression(forKeyPath: "opacity")
            style.addLayer(fill)
        }

        func syncZoneGlows(_ glows: [ZoneGlowOverlay], on mapView: MLNMapView) {
            let ids = glows.map(\.id)
            guard ids != renderedZoneIDs, let source = zoneSource else {
                if zoneSource == nil { return }
                if ids == renderedZoneIDs { return }
                return
            }
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

        // MARK: Memory pins

        func syncPins(own: [CachedOwnPin], revealed: [RevealedMemoryPin], on mapView: MLNMapView) {
            let ownIDs = own.map(\.memoryID)
            let revealedIDs = revealed.map(\.memoryID)
            guard ownIDs != renderedOwnIDs || revealedIDs != renderedRevealedIDs else { return }
            renderedOwnIDs = ownIDs
            renderedRevealedIDs = revealedIDs

            if let existing = mapView.annotations {
                mapView.removeAnnotations(existing)
            }

            var annotations: [MLNPointAnnotation] = []
            annotations.reserveCapacity(own.count + revealed.count)
            for pin in own {
                let a = PinAnnotation(style: .own)
                a.coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
                a.title = "Your memory"
                annotations.append(a)
            }
            for pin in revealed {
                let a = PinAnnotation(style: .revealed)
                a.coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
                a.title = "Memory nearby"
                annotations.append(a)
            }
            mapView.addAnnotations(annotations)
        }

        func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
            guard let pin = annotation as? PinAnnotation else { return nil }
            let reuseID = pin.style == .own ? Self.ownReuseID : Self.revealedReuseID
            if let cached = mapView.dequeueReusableAnnotationImage(withIdentifier: reuseID) {
                return cached
            }
            let image = Self.markerImage(for: pin.style)
            return MLNAnnotationImage(image: image, reuseIdentifier: reuseID)
        }

        // MARK: Marker rendering (SF Symbol → tinted UIImage, parity with PinDropMarker)

        private static func markerImage(for style: PinAnnotation.Style) -> UIImage {
            let symbolName = style == .own ? "mappin.circle.fill" : "mappin.and.ellipse"
            let pointSize: CGFloat = style == .own ? 28 : 24
            let tint = UIColor(style == .own ? LegacyColor.accent : LegacyColor.accent.opacity(0.85))
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            let base = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
            let tinted = base.withTintColor(tint, renderingMode: .alwaysOriginal)

            // Bake a soft drop shadow so pins read against busy tiles (matches PinDropMarker).
            let inset: CGFloat = 4
            let size = CGSize(width: tinted.size.width + inset * 2, height: tinted.size.height + inset * 2)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                ctx.cgContext.setShadow(
                    offset: CGSize(width: 0, height: 2),
                    blur: 3,
                    color: UIColor.black.withAlphaComponent(0.35).cgColor
                )
                tinted.draw(at: CGPoint(x: inset, y: inset))
            }
        }

        // MARK: Geometry

        /// Approximates a circle of `radiusMeters` around `center` as a closed ring of
        /// lat/lng points (equirectangular projection — accurate enough at zone scale).
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
    let style: Style
    init(style: Style) {
        self.style = style
        super.init()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// The single source of truth for the Wander map's look & camera.
/// Swap `current` to any OpenFreeMap style to retheme the entire map.
enum WanderMapStyle {
    /// OpenFreeMap "Liberty" — free, key-less, MapTiler-flavored basemap.
    /// Alternatives (same host): `positron` (minimal/light), `bright`, `dark`, `fiord`.
    static let current = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    /// Camera tilt in degrees — the lean-into-the-world angle.
    static let pitch: CGFloat = 55

    /// Street-level zoom for the follow camera.
    static let streetZoom: Double = 16.5
}
#endif
