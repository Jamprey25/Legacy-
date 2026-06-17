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

    func testRankingPrefersDenseRecencySpreadCluster() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let dense = (0..<5).map { i in
            PhotoGeoSample(
                id: "d\(i)",
                lat: 37.7749 + Double(i) * 0.00001,
                lng: -122.4194,
                capturedAt: base.addingTimeInterval(Double(i) * 86_400)
            )
        }
        let sparse = [
            PhotoGeoSample(id: "s1", lat: 40.0, lng: -74.0, capturedAt: base),
        ]

        let clusters = PhotoClusterEngine.cluster(samples: dense + sparse)
        XCTAssertEqual(clusters.first?.photoCount, 5)
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
