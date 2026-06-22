@testable import ImportFeature
import XCTest

final class ImportCoordinatorTests: XCTestCase {
    func testIdempotencyKeyIsStableForSameDayAndClusters() {
        let ref = Date(timeIntervalSince1970: 1_700_000_000)
        let clusters = [
            PhotoCluster(id: "b", centroidLat: 1, centroidLng: 2, photoCount: 3, sampleIDs: ["s1"], score: 1, date: ref),
            PhotoCluster(id: "a", centroidLat: 3, centroidLng: 4, photoCount: 5, sampleIDs: ["s2"], score: 2, date: ref),
        ]
        let first = ImportCoordinator.idempotencyKey(for: clusters)
        let second = ImportCoordinator.idempotencyKey(for: clusters.reversed())
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("import:"))
    }

    func testCapturedAtUsesEarliestSampleInCluster() throws {
        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        let cluster = PhotoCluster(
            id: "c1",
            centroidLat: 0,
            centroidLng: 0,
            photoCount: 2,
            sampleIDs: ["a", "b"],
            score: 1,
            date: early
        )
        let samples = [
            PhotoGeoSample(id: "a", lat: 0, lng: 0, capturedAt: late),
            PhotoGeoSample(id: "b", lat: 0, lng: 0, capturedAt: early),
        ]
        let iso = ImportCoordinator.capturedAtISO(for: cluster, samples: samples)
        let parsed = ISO8601DateFormatter().date(from: iso)
        XCTAssertEqual(parsed, early)
    }
}
