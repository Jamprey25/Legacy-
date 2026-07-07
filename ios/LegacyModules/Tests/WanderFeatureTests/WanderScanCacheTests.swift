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

    func testLoadNeverRestoresInRange() {
        // Range eligibility must come from a live scan — a cached `inRange: true`
        // would surface "unlock now" UI the server will reject (user has moved).
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
        let restored = WanderScanCache.load()
        XCTAssertEqual(restored.count, 1)
        XCTAssertFalse(restored[0].inRange)
        // Warmth survives — that's what the cache is for (DEC-29 offline near UX).
        XCTAssertEqual(restored[0].warmth, "coarse")
    }
}
