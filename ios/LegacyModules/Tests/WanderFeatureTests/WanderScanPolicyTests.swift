import APIClient
import DesignSystem
import Foundation
import XCTest
@testable import WanderFeature

final class WanderScanPolicyTests: XCTestCase {

    func testMaxWarmthPicksHighestBand() throws {
        let teasers = try [
            makeTeaser(warmth: "coarse"),
            makeTeaser(warmth: "in_bubble"),
            makeTeaser(warmth: "approaching"),
        ]

        let level = WanderScanPolicy.maxWarmthLevel(from: teasers)
        XCTAssertEqual(level, .inBubble)
        XCTAssertEqual(level.intensity, WarmthLevel.inBubble.intensity)
    }

    func testMaxWarmthEmptyReturnsNone() {
        XCTAssertEqual(WanderScanPolicy.maxWarmthLevel(from: []), .none)
    }

    func testMaxWarmthIgnoresUnknownValues() throws {
        let teasers = try [makeTeaser(warmth: "unknown_band")]
        XCTAssertEqual(WanderScanPolicy.maxWarmthLevel(from: teasers), .none)
    }

    private func makeTeaser(warmth: String) throws -> Teaser {
        let json = """
        {
          "memory_id": "\(UUID().uuidString)",
          "drop_date": "2026-06-16",
          "owner_display": "Alex",
          "is_own": false,
          "in_range": false,
          "warmth": "\(warmth)",
          "scan_status": "clear"
        }
        """
        return try JSONDecoder().decode(Teaser.self, from: Data(json.utf8))
    }
}
