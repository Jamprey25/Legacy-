import Foundation

/// A photo location sample used for on-device clustering. No image bytes — metadata only.
public struct PhotoGeoSample: Sendable, Equatable, Identifiable {
    public let id: String
    public let lat: Double
    public let lng: Double
    public let capturedAt: Date

    public init(id: String, lat: Double, lng: Double, capturedAt: Date) {
        self.id = id
        self.lat = lat
        self.lng = lng
        self.capturedAt = capturedAt
    }
}

/// One merged cluster representing a single visit to a place, ready for user selection.
public struct PhotoCluster: Sendable, Equatable, Identifiable {
    public let id: String
    public let centroidLat: Double
    public let centroidLng: Double
    public let photoCount: Int
    public let sampleIDs: [String]
    public let score: Double
    /// Earliest capture date in the cluster — represents when this visit happened.
    public let date: Date

    public init(
        id: String,
        centroidLat: Double,
        centroidLng: Double,
        photoCount: Int,
        sampleIDs: [String],
        score: Double,
        date: Date
    ) {
        self.id = id
        self.centroidLat = centroidLat
        self.centroidLng = centroidLng
        self.photoCount = photoCount
        self.sampleIDs = sampleIDs
        self.score = score
        self.date = date
    }
}

/// Visit-based grid clustering (~150 m cells × calendar day).
///
/// Key insight: groups photos by *both* location and the day they were taken, so visiting
/// the same place on 10 different days produces 10 distinct memories rather than 1.
/// Adjacent cells on the same day are BFS-merged as usual (handles photos spread across
/// a restaurant, a street corner, and the park nearby taken on the same afternoon).
public enum PhotoClusterEngine {
    /// Approximate cell size in degrees latitude (~150 m at mid-latitudes).
    public static let cellSizeDegrees: Double = 0.00135

    public static func cluster(
        samples: [PhotoGeoSample],
        maxClusters: Int = 500
    ) -> [PhotoCluster] {
        guard !samples.isEmpty else { return [] }

        var cellToSamples: [CellKey: [PhotoGeoSample]] = [:]
        for sample in samples {
            let key = CellKey(lat: sample.lat, lng: sample.lng, cellSize: cellSizeDegrees, capturedAt: sample.capturedAt)
            cellToSamples[key, default: []].append(sample)
        }

        var visited = Set<CellKey>()
        var merged: [[PhotoGeoSample]] = []

        for key in cellToSamples.keys where !visited.contains(key) {
            var queue = [key]
            var group: [PhotoGeoSample] = []
            visited.insert(key)

            while let current = queue.popLast() {
                group.append(contentsOf: cellToSamples[current] ?? [])
                for neighbor in current.neighbors() where cellToSamples[neighbor] != nil && !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }

            merged.append(group)
        }

        let ranked = merged
            .map { makeCluster(from: $0) }
            .sorted { $0.score > $1.score }

        return Array(ranked.prefix(maxClusters))
    }

    private static func makeCluster(from samples: [PhotoGeoSample]) -> PhotoCluster {
        let count = samples.count
        let lat = samples.map(\.lat).reduce(0, +) / Double(count)
        let lng = samples.map(\.lng).reduce(0, +) / Double(count)
        let dates = samples.map(\.capturedAt)
        let earliest = dates.min() ?? Date()

        // Rank by recency: a recent visit with fewer photos beats an older one with more.
        // Decay factor halves over ~1 year so very old visits sink to the bottom.
        let daysSinceVisit = max(0, Date().timeIntervalSince(earliest)) / 86_400
        let recencyBonus = 1.0 / (1.0 + daysSinceVisit / 365.0)
        let score = Double(count) * (1.0 + recencyBonus)

        let ids = samples.map(\.id)
        return PhotoCluster(
            id: "cluster-\(ids.sorted().joined(separator: "-").hashValue)",
            centroidLat: lat,
            centroidLng: lng,
            photoCount: count,
            sampleIDs: ids,
            score: score,
            date: earliest
        )
    }
}

private struct CellKey: Hashable {
    let row: Int
    let col: Int
    /// Calendar day in device timezone ("YYYY-MM-DD"). Two photos at the same grid cell
    /// but on different days get different keys → separate visit clusters.
    let dayBucket: String

    init(lat: Double, lng: Double, cellSize: Double, capturedAt: Date) {
        row = Int(floor(lat / cellSize))
        col = Int(floor(lng / cellSize))
        dayBucket = Self.dayString(for: capturedAt)
    }

    /// Only expand spatially — neighbors must share the same calendar day.
    func neighbors() -> [CellKey] {
        [
            CellKey(row: row - 1, col: col - 1, dayBucket: dayBucket),
            CellKey(row: row - 1, col: col,     dayBucket: dayBucket),
            CellKey(row: row - 1, col: col + 1, dayBucket: dayBucket),
            CellKey(row: row,     col: col - 1, dayBucket: dayBucket),
            CellKey(row: row,     col: col + 1, dayBucket: dayBucket),
            CellKey(row: row + 1, col: col - 1, dayBucket: dayBucket),
            CellKey(row: row + 1, col: col,     dayBucket: dayBucket),
            CellKey(row: row + 1, col: col + 1, dayBucket: dayBucket),
        ]
    }

    private init(row: Int, col: Int, dayBucket: String) {
        self.row = row
        self.col = col
        self.dayBucket = dayBucket
    }

    private static func dayString(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
