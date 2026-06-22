import APIClient
import Foundation
import LocationEngine

/// Map overlay for a precision-7 coarse zone (`zones[]` from `/scan`).
public struct ZoneGlowOverlay: Sendable, Equatable, Identifiable {
    public let geohashPrefix: String
    public let centerLat: Double
    public let centerLng: Double
    public let radiusMeters: Double
    public let count: Int

    public var id: String { geohashPrefix }

    /// Opacity scales gently with memory count — never fully opaque (privacy + legibility).
    public var opacity: Double {
        min(0.42, 0.12 + Double(count) * 0.06)
    }

    public static func build(from zones: [CoarseZone]) -> [ZoneGlowOverlay] {
        zones.compactMap { zone in
            guard let decoded = GeohashCell.decode(prefix: zone.geohashPrefix) else { return nil }
            return ZoneGlowOverlay(
                geohashPrefix: zone.geohashPrefix,
                centerLat: decoded.lat,
                centerLng: decoded.lng,
                radiusMeters: decoded.radiusMeters,
                count: zone.count
            )
        }
    }
}
