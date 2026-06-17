import APIClient
@testable import DropFeature
import Foundation
import XCTest

final class DropComposeMappingTests: XCTestCase {
    func testFixedDateSealPayload() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = DropComposeMapping.sealPayload(from: .fixedDate(date))
        guard case .fixedDate(let openAt) = payload else {
            return XCTFail("Expected fixed_date payload")
        }
        XCTAssertTrue(openAt.contains("2023"))
    }

    func testDurationSealPayload() {
        let payload = DropComposeMapping.sealPayload(from: .duration(hours: 48))
        guard case .duration(let hours) = payload else {
            return XCTFail("Expected duration payload")
        }
        XCTAssertEqual(hours, 48)
    }

    func testConditionIncludesFallback() {
        let fallback = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = DropComposeMapping.conditionPayload(
            from: .timeOfDay(afterHour: 18, beforeHour: 22, fallback: fallback)
        )
        guard case .timeOfDay(_, _, let iso) = payload else {
            return XCTFail("Expected time_of_day payload")
        }
        XCTAssertFalse(iso.isEmpty)
    }
}
