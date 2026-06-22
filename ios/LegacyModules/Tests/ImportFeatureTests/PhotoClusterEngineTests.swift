import Foundation
import XCTest
@testable import ImportFeature

final class PhotoClusterEngineTests: XCTestCase {

    func testEmptyInputReturnsNoClusters() {
        XCTAssertTrue(PhotoClusterEngine.cluster(samples: []).isEmpty)
    }

    func testNearbySamplesMergeIntoOneCluster() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            PhotoGeoSample(id: "a", lat: 37.7749, lng: -122.4194, capturedAt: base),
            PhotoGeoSample(id: "b", lat: 37.7750, lng: -122.4195, capturedAt: base.addingTimeInterval(3600)),
        ]

        let clusters = PhotoClusterEngine.cluster(samples: samples)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].photoCount, 2)
        XCTAssertEqual(clusters[0].sampleIDs.sorted(), ["a", "b"])
    }

    func testDistantSamplesStaySeparate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = [
            PhotoGeoSample(id: "sf", lat: 37.7749, lng: -122.4194, capturedAt: date),
            PhotoGeoSample(id: "la", lat: 34.0522, lng: -118.2437, capturedAt: date),
        ]

        XCTAssertEqual(PhotoClusterEngine.cluster(samples: samples).count, 2)
    }

    /// Visit-based: same place, same day, multiple photos → still one cluster.
    func testSamePlaceSameDayMergesIntoOneVisit() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let samples = (0..<4).map { i in
            PhotoGeoSample(
                id: "p\(i)",
                lat: 37.7749 + Double(i) * 0.00001,
                lng: -122.4194,
                capturedAt: day.addingTimeInterval(Double(i) * 1800) // 30 min apart, same day
            )
        }
        let clusters = PhotoClusterEngine.cluster(samples: samples)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].photoCount, 4)
    }

    /// Visit-based: same place, different days → separate memories (core new behaviour).
    func testSamePlaceDifferentDaysProducesSeparateClusters() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let day1 = base
        let day2 = base.addingTimeInterval(86_400 * 3)   // 3 days later
        let day3 = base.addingTimeInterval(86_400 * 10)  // 10 days later
        let samples = [
            PhotoGeoSample(id: "a", lat: 37.7749, lng: -122.4194, capturedAt: day1),
            PhotoGeoSample(id: "b", lat: 37.7749, lng: -122.4194, capturedAt: day2),
            PhotoGeoSample(id: "c", lat: 37.7749, lng: -122.4194, capturedAt: day3),
        ]
        let clusters = PhotoClusterEngine.cluster(samples: samples)
        // One visit per calendar day → 3 clusters
        XCTAssertEqual(clusters.count, 3)
        clusters.forEach { XCTAssertEqual($0.photoCount, 1) }
    }

    func testRecentVisitRanksAboveOlderVisitOfSameSize() {
        let recentDate = Date().addingTimeInterval(-86_400 * 2)        // 2 days ago
        let oldDate    = Date().addingTimeInterval(-86_400 * 400)      // > 1 year ago
        let recent = [PhotoGeoSample(id: "r1", lat: 37.7749, lng: -122.4194, capturedAt: recentDate)]
        let old    = [PhotoGeoSample(id: "o1", lat: 40.0,    lng: -74.0,    capturedAt: oldDate)]
        let clusters = PhotoClusterEngine.cluster(samples: recent + old)
        XCTAssertEqual(clusters.count, 2)
        // Recent (daysSince ≈ 2) → recencyBonus ≈ 0.99; old (daysSince ≈ 400) → ≈ 0.48
        // Both 1-photo clusters, so recent wins on score = 1 × (1 + bonus)
        XCTAssertLessThan(
            Date().timeIntervalSince(clusters.first!.date),
            Date().timeIntervalSince(clusters.last!.date)
        )
    }

    func testMaxClustersCap() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var samples: [PhotoGeoSample] = []
        for i in 0..<60 {
            samples.append(
                PhotoGeoSample(
                    id: "p\(i)",
                    lat: Double(i),
                    lng: Double(i),
                    capturedAt: date
                )
            )
        }

        XCTAssertEqual(PhotoClusterEngine.cluster(samples: samples, maxClusters: 50).count, 50)
    }
}
