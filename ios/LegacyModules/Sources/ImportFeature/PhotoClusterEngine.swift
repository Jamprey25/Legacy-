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

/// One merged cluster ready for user selection before import.
public struct PhotoCluster: Sendable, Equatable, Identifiable {
    public let id: String
    public let centroidLat: Double
    public let centroidLng: Double
    public let photoCount: Int
    public let sampleIDs: [String]
    public let score: Double

    public init(
        id: String,
        centroidLat: Double,
        centroidLng: Double,
        photoCount: Int,
        sampleIDs: [String],
        score: Double
    ) {
        self.id = id
        self.centroidLat = centroidLat
        self.centroidLng = centroidLng
        self.photoCount = photoCount
        self.sampleIDs = sampleIDs
        self.score = score
    }
}

/// Grid-snap clustering (~150 m cells), merge adjacent occupied cells, rank by count × recency spread.
public enum PhotoClusterEngine {
    /// Approximate cell size in degrees latitude (~150 m at mid-latitudes).
    public static let cellSizeDegrees: Double = 0.00135

    public static func cluster(
        samples: [PhotoGeoSample],
        maxClusters: Int = 50
    ) -> [PhotoCluster] {
        guard !samples.isEmpty else { return [] }

        var cellToSamples: [CellKey: [PhotoGeoSample]] = [:]
        for sample in samples {
            let key = CellKey(lat: sample.lat, lng: sample.lng, cellSize: cellSizeDegrees)
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
        let spreadDays = (dates.max()?.timeIntervalSince(dates.min() ?? Date()) ?? 0) / 86_400
        let recencyFactor = 1 + min(spreadDays / 30, 1)
        let score = Double(count) * recencyFactor
        let ids = samples.map(\.id)

        return PhotoCluster(
            id: "cluster-\(ids.sorted().joined(separator: "-").hashValue)",
            centroidLat: lat,
            centroidLng: lng,
            photoCount: count,
            sampleIDs: ids,
            score: score
        )
    }
}

private struct CellKey: Hashable {
    let row: Int
    let col: Int

    init(lat: Double, lng: Double, cellSize: Double) {
        row = Int(floor(lat / cellSize))
        col = Int(floor(lng / cellSize))
    }

    func neighbors() -> [CellKey] {
        [
            CellKey(row: row - 1, col: col),
            CellKey(row: row + 1, col: col),
            CellKey(row: row, col: col - 1),
            CellKey(row: row, col: col + 1),
            CellKey(row: row - 1, col: col - 1),
            CellKey(row: row - 1, col: col + 1),
            CellKey(row: row + 1, col: col - 1),
            CellKey(row: row + 1, col: col + 1),
        ]
    }

    private init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}
