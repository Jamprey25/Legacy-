import CoreLocation
import LocationEngine
import XCTest

final class RegionRotationPolicyTests: XCTestCase {
    func testOwnPinsSortedByDistance() {
        let reference = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let pins = [
            CachedOwnPin(memoryID: "far", lat: 10, lng: 10, dropDate: "2024-01-01", thumbnailURL: nil, cachedAt: Date()),
            CachedOwnPin(memoryID: "near", lat: 0.001, lng: 0.001, dropDate: "2024-01-02", thumbnailURL: nil, cachedAt: Date()),
        ]
        let slots = RegionRotationPolicy.rotate(reference: reference, ownPins: pins, coarseZones: [])
        XCTAssertEqual(slots.first?.id, "ownnear")
    }

    func testCoarseZonesFillRemainingBudget() {
        let reference = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let coarse = [
            CoarseZoneRecord(geohashPrefix: "9q8yy", centerLat: 1, centerLng: 1),
        ]
        let slots = RegionRotationPolicy.rotate(reference: reference, ownPins: [], coarseZones: coarse)
        XCTAssertEqual(slots.count, 1)
        if case .coarseZone(let prefix, _, _, _) = slots[0] {
            XCTAssertEqual(prefix, "9q8yy")
        } else {
            XCTFail("Expected coarse zone slot")
        }
    }

    func testMaxRegionsCap() {
        let reference = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let pins = (0..<30).map { i in
            CachedOwnPin(
                memoryID: "m\(i)",
                lat: Double(i) * 0.01,
                lng: 0,
                dropDate: "2024-01-01",
                thumbnailURL: nil,
                cachedAt: Date()
            )
        }
        let slots = RegionRotationPolicy.rotate(reference: reference, ownPins: pins, coarseZones: [])
        XCTAssertLessThanOrEqual(slots.count, RegionRotationPolicy.maxRegions)
    }
}
