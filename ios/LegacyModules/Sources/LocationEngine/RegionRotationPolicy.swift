import CoreLocation
import Foundation

/// A monitor slot — either an own-memory pin (exact coords allowed) or a coarse geohash cell (no point coords for others).
public enum RegionSlot: Sendable, Equatable, Identifiable {
    case ownPin(memoryID: String, lat: Double, lng: Double, radiusM: Double)
    case coarseZone(geohashPrefix: String, centerLat: Double, centerLng: Double, radiusM: Double)

    /// CLMonitor condition identifiers must be alphanumeric (no punctuation).
    public var id: String {
        switch self {
        case .ownPin(let memoryID, _, _, _):
            return Self.clMonitorIdentifier(prefix: "own", raw: memoryID)
        case .coarseZone(let prefix, _, _, _):
            return Self.clMonitorIdentifier(prefix: "coarse", raw: prefix)
        }
    }

    private static func clMonitorIdentifier(prefix: String, raw: String) -> String {
        let body = raw.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        return prefix + body
    }

    public var coordinate: (lat: Double, lng: Double) {
        switch self {
        case .ownPin(_, let lat, let lng, _):
            return (lat, lng)
        case .coarseZone(_, let lat, let lng, _):
            return (lat, lng)
        }
    }

    public var radiusM: Double {
        switch self {
        case .ownPin(_, _, _, let radius):
            return radius
        case .coarseZone(_, _, _, let radius):
            return radius
        }
    }
}

/// Picks which regions to arm under the iOS ~20 region cap (engineering-plan §7).
public enum RegionRotationPolicy {
    public static let maxRegions = 19
    public static let ownPinBudget = 14
    public static let coarseZoneBudget = 5
    public static let defaultOwnPinRadiusM = 120.0
    public static let defaultCoarseRadiusM = 2_500.0

    /// Sort own pins by distance to `reference`, take `ownPinBudget`, then coarse zones, cap at `maxRegions`.
    public static func rotate(
        reference: CLLocationCoordinate2D,
        ownPins: [CachedOwnPin],
        coarseZones: [CoarseZoneRecord],
        maxRegions: Int = maxRegions
    ) -> [RegionSlot] {
        let referenceLocation = CLLocation(latitude: reference.latitude, longitude: reference.longitude)

        let sortedOwn = ownPins
            .map { pin -> (CachedOwnPin, CLLocationDistance) in
                let loc = CLLocation(latitude: pin.lat, longitude: pin.lng)
                return (pin, referenceLocation.distance(from: loc))
            }
            .sorted { $0.1 < $1.1 }
            .prefix(ownPinBudget)
            .map { pin, _ in
                RegionSlot.ownPin(
                    memoryID: pin.memoryID,
                    lat: pin.lat,
                    lng: pin.lng,
                    radiusM: defaultOwnPinRadiusM
                )
            }

        var slots = Array(sortedOwn)
        let remaining = max(0, maxRegions - slots.count)
        let coarseSlots = coarseZones.prefix(min(coarseZoneBudget, remaining)).map { zone in
            RegionSlot.coarseZone(
                geohashPrefix: zone.geohashPrefix,
                centerLat: zone.centerLat,
                centerLng: zone.centerLng,
                radiusM: defaultCoarseRadiusM
            )
        }
        slots.append(contentsOf: coarseSlots)
        return Array(slots.prefix(maxRegions))
    }
}

/// Coarse geohash cell metadata — prefix only, never a memory coordinate (DEC-16).
public struct CoarseZoneRecord: Sendable, Equatable, Codable, Identifiable {
    public let geohashPrefix: String
    public let centerLat: Double
    public let centerLng: Double

    public var id: String { geohashPrefix }

    public init(geohashPrefix: String, centerLat: Double, centerLng: Double) {
        self.geohashPrefix = geohashPrefix
        self.centerLng = centerLng
        self.centerLat = centerLat
    }
}

public enum CoarseZoneCache {
    private static let storageKey = "legacy.coarse-zones.v1"

    public static func load() -> [CoarseZoneRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let zones = try? JSONDecoder().decode([CoarseZoneRecord].self, from: data)
        else { return [] }
        return zones
    }

    public static func save(_ zones: [CoarseZoneRecord]) {
        guard let data = try? JSONEncoder().encode(zones) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    public static func merge(prefixes: [CoarseZoneRecord]) {
        var map = Dictionary(uniqueKeysWithValues: load().map { ($0.geohashPrefix, $0) })
        for zone in prefixes {
            map[zone.geohashPrefix] = zone
        }
        save(Array(map.values))
    }
}
