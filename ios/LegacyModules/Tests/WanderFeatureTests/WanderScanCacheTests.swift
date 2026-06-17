@testable import WanderFeature
import APIClient
import XCTest

final class WanderScanCacheTests: XCTestCase {
    override func tearDown() {
        WanderScanCache.clear()
        super.tearDown()
    }

    func testSaveAndLoadTeasers() {
        let teaser = Teaser(
            memoryID: "abc",
            thumbnailURL: nil,
            dropDate: "2024-01-01",
            ownerDisplay: "you",
            isOwn: true,
            inRange: true,
            warmth: "coarse",
            scanStatus: "clear"
        )
        WanderScanCache.save(teasers: [teaser])
        XCTAssertEqual(WanderScanCache.load().count, 1)
    }
}
