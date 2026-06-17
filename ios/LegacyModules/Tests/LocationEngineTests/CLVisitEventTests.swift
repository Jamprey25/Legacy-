import LocationEngine
import XCTest

final class CLVisitEventTests: XCTestCase {
    func testArrivalVisitUsesDistantFutureDeparture() {
        XCTAssertTrue(CLVisitEvent.isArrival(departureDate: Date.distantFuture))
    }

    func testDepartureVisitHasConcreteDepartureDate() {
        XCTAssertFalse(CLVisitEvent.isArrival(departureDate: Date()))
    }
}
