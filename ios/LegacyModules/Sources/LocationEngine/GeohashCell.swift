import Foundation

/// Decodes a geohash prefix to its cell center and approximate radius (standard base32 geohash).
public enum GeohashCell {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    public struct Decoded: Sendable, Equatable {
        public let lat: Double
        public let lng: Double
        /// Half-height of the cell in degrees latitude.
        public let latError: Double
        /// Half-width of the cell in degrees longitude.
        public let lngError: Double

        /// Approximate circle radius in metres for map overlays (uses the larger half-axis).
        public var radiusMeters: Double {
            let latM = latError * 111_320
            let lngM = lngError * 111_320 * max(0.1, cos(lat * .pi / 180))
            return max(latM, lngM)
        }
    }

    public static func decode(prefix: String) -> Decoded? {
        guard !prefix.isEmpty else { return nil }

        var minLat = -90.0, maxLat = 90.0
        var minLng = -180.0, maxLng = 180.0
        var isEven = true

        for character in prefix {
            guard let index = base32.firstIndex(of: character) else { return nil }
            var bits = index
            for bit in (0..<5).reversed() {
                let bitN = (bits >> bit) & 1
                if isEven {
                    let mid = (minLng + maxLng) / 2
                    if bitN == 1 { minLng = mid } else { maxLng = mid }
                } else {
                    let mid = (minLat + maxLat) / 2
                    if bitN == 1 { minLat = mid } else { maxLat = mid }
                }
                isEven.toggle()
            }
        }

        return Decoded(
            lat: (minLat + maxLat) / 2,
            lng: (minLng + maxLng) / 2,
            latError: (maxLat - minLat) / 2,
            lngError: (maxLng - minLng) / 2
        )
    }
}
