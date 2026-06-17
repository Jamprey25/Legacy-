@testable import WanderFeature
import XCTest

final class OwnMemoryPinCacheTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "legacy.own-memory-pins.v1")
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() {
        let pin = CachedOwnPin(
            memoryID: "mem-1",
            lat: 37.77,
            lng: -122.42,
            dropDate: "2024-01-01",
            thumbnailURL: "https://example.com/t.jpg",
            cachedAt: Date()
        )
        OwnMemoryPinCache.save(pin)
        let loaded = OwnMemoryPinCache.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.memoryID, "mem-1")
    }

    func testRemovePin() {
        OwnMemoryPinCache.save(
            CachedOwnPin(
                memoryID: "mem-2",
                lat: 1,
                lng: 2,
                dropDate: "2024-02-02",
                thumbnailURL: nil,
                cachedAt: Date()
            )
        )
        OwnMemoryPinCache.remove(memoryID: "mem-2")
        XCTAssertTrue(OwnMemoryPinCache.load().isEmpty)
    }
}
