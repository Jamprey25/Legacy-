import Foundation

/// Cached drop location for the user's own memories only.
/// Non-owned coordinates must never persist on device (M2 privacy invariant).
public struct CachedOwnPin: Codable, Sendable, Equatable, Identifiable {
    public let memoryID: String
    public let lat: Double
    public let lng: Double
    public let dropDate: String
    public let thumbnailURL: String?
    public let cachedAt: Date

    public var id: String { memoryID }

    public init(
        memoryID: String,
        lat: Double,
        lng: Double,
        dropDate: String,
        thumbnailURL: String?,
        cachedAt: Date
    ) {
        self.memoryID = memoryID
        self.lat = lat
        self.lng = lng
        self.dropDate = dropDate
        self.thumbnailURL = thumbnailURL
        self.cachedAt = cachedAt
    }
}

public enum OwnMemoryPinCache {
    private static let storageKey = "legacy.own-memory-pins.v1"
    private static let maxPins = 200

    public static func load() -> [CachedOwnPin] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let pins = try? JSONDecoder().decode([CachedOwnPin].self, from: data)
        else { return [] }
        return pins
    }

    public static func save(_ pin: CachedOwnPin) {
        var pins = load().filter { $0.memoryID != pin.memoryID }
        pins.insert(pin, at: 0)
        if pins.count > maxPins {
            pins = Array(pins.prefix(maxPins))
        }
        guard let data = try? JSONEncoder().encode(pins) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    public static func remove(memoryID: String) {
        let pins = load().filter { $0.memoryID != memoryID }
        guard let data = try? JSONEncoder().encode(pins) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
