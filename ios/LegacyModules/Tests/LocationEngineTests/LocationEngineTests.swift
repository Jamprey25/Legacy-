import CoreLocation
import XCTest
@testable import LocationEngine

@MainActor
final class LocationEngineTests: XCTestCase {
    func testMovementGateTriggersAfterDistance() {
        let origin = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let moved = CLLocation(latitude: 37.7752, longitude: -122.4194)

        XCTAssertTrue(
            ScanMovementGate.shouldTriggerScan(for: moved, lastScanLocation: origin, lastScanDate: Date())
        )
    }

    func testMovementGateTriggersAfterTime() {
        let location = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let oldDate = Date().addingTimeInterval(-31)

        XCTAssertTrue(
            ScanMovementGate.shouldTriggerScan(for: location, lastScanLocation: location, lastScanDate: oldDate)
        )
    }
}
