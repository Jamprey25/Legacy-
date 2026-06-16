import XCTest
@testable import DesignSystem

final class DesignSystemTests: XCTestCase {
    func testVersionIsSet() {
        XCTAssertEqual(DesignSystem.version, "0.1.0")
    }
}
