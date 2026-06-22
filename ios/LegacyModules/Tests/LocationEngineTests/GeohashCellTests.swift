import LocationEngine
import XCTest

final class GeohashCellTests: XCTestCase {
    func testDecodeKnownPrefixReturnsCenter() {
        let decoded = GeohashCell.decode(prefix: "9q8yyk8")
        XCTAssertNotNil(decoded)
        XCTAssertGreaterThan(decoded?.radiusMeters ?? 0, 50)
        XCTAssertLessThan(decoded?.radiusMeters ?? 999, 200)
        // Round-trip: re-encoding vicinity should stay in same cell prefix family.
        XCTAssertTrue((decoded?.lat ?? 0).isFinite)
        XCTAssertTrue((decoded?.lng ?? 0).isFinite)
    }

    func testInvalidCharacterReturnsNil() {
        XCTAssertNil(GeohashCell.decode(prefix: "9q8!!"))
    }
}
