import CoreLocation
import XCTest
@testable import LocationEngine

final class LocationEngineTests: XCTestCase {

    func testMovementGateTriggersAfterDistance() {
        let origin = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let moved = CLLocation(latitude: 37.7752, longitude: -122.4194) // ~33m north

        XCTAssertTrue(
            ScanMovementGate.shouldTriggerScan(
                for: moved,
                lastScanLocation: origin,
                lastScanDate: Date()
            )
        )
    }

    func testMovementGateDoesNotTriggerWhenStill() {
        let here = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let barelyMoved = CLLocation(latitude: 37.77491, longitude: -122.4194) // ~1m

        XCTAssertFalse(
            ScanMovementGate.shouldTriggerScan(
                for: barelyMoved,
                lastScanLocation: here,
                lastScanDate: Date()
            )
        )
    }

    func testMovementGateTriggersAfterTime() {
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let oldDate = Date().addingTimeInterval(-31)

        XCTAssertTrue(
            ScanMovementGate.shouldTriggerScan(
                for: location,
                lastScanLocation: location,
                lastScanDate: oldDate
            )
        )
    }

    func testMovementGateTriggersOnFirstFix() {
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)

        XCTAssertTrue(
            ScanMovementGate.shouldTriggerScan(
                for: location,
                lastScanLocation: nil,
                lastScanDate: nil
            )
        )
    }

    func testLocationFixReducesToContractFields() {
        let cl = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 1.5, longitude: -2.5),
            altitude: 0,
            horizontalAccuracy: 12.0,
            verticalAccuracy: 5,
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        let fix = LocationFix(cl)

        XCTAssertEqual(fix.lat, 1.5)
        XCTAssertEqual(fix.lng, -2.5)
        XCTAssertEqual(fix.accuracyM, 12.0)
        XCTAssertEqual(fix.timestamp, Date(timeIntervalSince1970: 1000))
    }
}
