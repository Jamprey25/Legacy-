#if os(iOS)
import CoreLocation

/// Reverse-geocodes a cluster's centroid into a short, human place label
/// ("Dolores Park, San Francisco") so the import list reads like places, not dates.
///
/// Lazy + cached + serialized. The actor isolates the cache; each lookup uses a fresh
/// `CLGeocoder` to avoid "geocoder busy" collisions under actor reentrancy. Results are
/// cached by ~110 m bucket so nearby centroids share one network lookup.
public actor PlaceNameResolver {
    public static let shared = PlaceNameResolver()

    private var cache: [String: String] = [:]

    public init() {}

    public func placeName(lat: Double, lng: Double) async -> String? {
        let key = Self.cacheKey(lat: lat, lng: lng)
        if let cached = cache[key] { return cached }

        let location = CLLocation(latitude: lat, longitude: lng)
        guard let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
              let placemark = placemarks.first,
              let label = Self.shortLabel(from: placemark) else {
            return nil
        }

        cache[key] = label
        return label
    }

    /// ~110 m bucketing (3 decimal places of degrees) so adjacent centroids collapse
    /// onto a single cache slot and one geocoder request.
    private static func cacheKey(lat: Double, lng: Double) -> String {
        String(format: "%.3f,%.3f", lat, lng)
    }

    /// Prefer a named point of interest, then neighborhood, then city. Append the city
    /// for context when the primary label isn't already the city itself.
    private static func shortLabel(from placemark: CLPlacemark) -> String? {
        let primary = placemark.areasOfInterest?.first
            ?? placemark.subLocality
            ?? placemark.locality
            ?? placemark.name
        guard let primary else { return nil }

        if let city = placemark.locality, city != primary {
            return "\(primary), \(city)"
        }
        return primary
    }
}
#endif
