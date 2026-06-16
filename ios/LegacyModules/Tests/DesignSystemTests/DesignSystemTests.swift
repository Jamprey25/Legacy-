import XCTest
@testable import DesignSystem

final class DesignSystemTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(DesignSystem.version, "0.1.0")
    }

    func testWarmthLevelParsesContractValues() {
        XCTAssertEqual(WarmthLevel(contractValue: "coarse"), .coarse)
        XCTAssertEqual(WarmthLevel(contractValue: "approaching"), .approaching)
        XCTAssertEqual(WarmthLevel(contractValue: "in_bubble"), .inBubble)
    }

    func testWarmthLevelUnknownDegradesToNone() {
        XCTAssertEqual(WarmthLevel(contractValue: "north"), .none)
        XCTAssertEqual(WarmthLevel(contractValue: nil), .none)
    }

    func testWarmthIntensityIsMonotonic() {
        XCTAssertLessThan(WarmthLevel.none.intensity, WarmthLevel.coarse.intensity)
        XCTAssertLessThan(WarmthLevel.coarse.intensity, WarmthLevel.approaching.intensity)
        XCTAssertLessThan(WarmthLevel.approaching.intensity, WarmthLevel.inBubble.intensity)
    }
}
