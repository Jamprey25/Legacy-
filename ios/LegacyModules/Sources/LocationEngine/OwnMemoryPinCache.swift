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
    private static let sessionStartKey = "legacy.session.startedAt"
    private static let maxPins = 200

    /// Marks the start of the current authenticated session. Grace pins from `reconcile`
    /// must be cached after this time so a prior account's pins cannot leak on switch.
    public static func markSessionStart() {
        UserDefaults.standard.set(Date(), forKey: sessionStartKey)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

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
        persist(pins)
    }

    /// Reconcile the local cache against the authoritative owner list from the server.
    ///
    /// The map must show *every* own memory, not just the ones dropped/unlocked on this
    /// device — so a fresh install or new sign-in seeds from here. Server coordinates win
    /// (authoritative). A pin the server no longer returns is dropped (deleted elsewhere),
    /// *unless* it was cached within `graceInterval` — those are just-dropped pins the list
    /// endpoint may not have caught up to yet, so we keep them to avoid a flicker.
    public static func reconcile(serverPins: [CachedOwnPin], graceInterval: TimeInterval = 600) {
        let now = Date()
        let sessionStart = UserDefaults.standard.object(forKey: sessionStartKey) as? Date ?? .distantPast
        let serverIDs = Set(serverPins.map(\.memoryID))
        var result = serverPins
        for pin in load() where !serverIDs.contains(pin.memoryID) {
            let withinGrace = now.timeIntervalSince(pin.cachedAt) < graceInterval
            let fromCurrentSession = pin.cachedAt >= sessionStart
            if withinGrace, fromCurrentSession {
                result.append(pin)
            }
        }
        persist(Array(result.prefix(maxPins)))
    }

    private static func persist(_ pins: [CachedOwnPin]) {
        guard let data = try? JSONEncoder().encode(pins) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
