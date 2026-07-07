import APIClient
import Foundation

/// Persists the last successful scan teasers for offline warmth (no coordinates — contract §4).
public enum WanderScanCache {
    private static let storageKey = "legacy.wander-scan.v1"
    private static let maxAge: TimeInterval = 24 * 60 * 60

    private struct CachedTeaser: Codable, Sendable {
        let memoryID: String
        let thumbnailURL: String?
        let dropDate: String
        let ownerDisplay: String
        let isOwn: Bool
        let inRange: Bool
        let warmth: String
        let scanStatus: String

        enum CodingKeys: String, CodingKey {
            case memoryID = "memory_id"
            case thumbnailURL = "thumbnail_url"
            case dropDate = "drop_date"
            case ownerDisplay = "owner_display"
            case isOwn = "is_own"
            case inRange = "in_range"
            case warmth
            case scanStatus = "scan_status"
        }

        init(_ teaser: Teaser) {
            memoryID = teaser.memoryID
            thumbnailURL = teaser.thumbnailURL
            dropDate = teaser.dropDate
            ownerDisplay = teaser.ownerDisplay
            isOwn = teaser.isOwn
            inRange = teaser.inRange
            warmth = teaser.warmth
            scanStatus = teaser.scanStatus
        }

        var teaser: Teaser {
            Teaser(
                memoryID: memoryID,
                thumbnailURL: thumbnailURL,
                dropDate: dropDate,
                ownerDisplay: ownerDisplay,
                isOwn: isOwn,
                // Never restore in-range from cache: the user has likely moved since the
                // last scan, and a stale `true` surfaces "unlock now" UI (teaser tray,
                // pin halos) that the server will reject. The cache exists for offline
                // warmth (DEC-29); range eligibility must come from a live scan.
                inRange: false,
                warmth: warmth,
                scanStatus: scanStatus
            )
        }
    }

    private struct CachedScan: Codable, Sendable {
        let teasers: [CachedTeaser]
        let savedAt: Date
    }

    public static func save(teasers: [Teaser]) {
        let payload = CachedScan(teasers: teasers.map(CachedTeaser.init), savedAt: Date())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    public static func load() -> [Teaser] {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let cached = try? JSONDecoder().decode(CachedScan.self, from: data)
        else { return [] }

        guard Date().timeIntervalSince(cached.savedAt) <= maxAge else {
            clear()
            return []
        }
        return cached.teasers.map(\.teaser)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
