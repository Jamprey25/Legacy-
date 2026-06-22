import APIClient
import WanderFeature
import XCTest

final class ZoneGlowOverlayTests: XCTestCase {
    func testBuildFromZonesUsesGeohashCenter() {
        let overlays = ZoneGlowOverlay.build(from: [
            CoarseZone(geohashPrefix: "9q8yyk8", count: 3),
        ])
        XCTAssertEqual(overlays.count, 1)
        XCTAssertEqual(overlays[0].count, 3)
        XCTAssertGreaterThan(overlays[0].opacity, 0.1)
        XCTAssertGreaterThan(overlays[0].radiusMeters, 50)
    }
}
