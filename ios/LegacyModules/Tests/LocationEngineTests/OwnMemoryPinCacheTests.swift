import LocationEngine
import XCTest

final class OwnMemoryPinCacheTests: XCTestCase {
    override func tearDown() {
        OwnMemoryPinCache.clear()
        UserDefaults.standard.removeObject(forKey: "legacy.session.startedAt")
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

    func testReconcileDropsGracePinsFromPriorSession() {
        let oldPin = CachedOwnPin(
            memoryID: "mem-old",
            lat: 1,
            lng: 2,
            dropDate: "2024-01-01",
            thumbnailURL: nil,
            cachedAt: Date().addingTimeInterval(-60)
        )
        OwnMemoryPinCache.save(oldPin)

        OwnMemoryPinCache.markSessionStart()

        OwnMemoryPinCache.reconcile(serverPins: [])

        XCTAssertTrue(OwnMemoryPinCache.load().isEmpty)
    }

    func testReconcileKeepsGracePinsFromCurrentSession() {
        OwnMemoryPinCache.markSessionStart()

        let freshPin = CachedOwnPin(
            memoryID: "mem-new",
            lat: 3,
            lng: 4,
            dropDate: "2024-02-02",
            thumbnailURL: nil,
            cachedAt: Date()
        )
        OwnMemoryPinCache.save(freshPin)

        OwnMemoryPinCache.reconcile(serverPins: [])

        XCTAssertEqual(OwnMemoryPinCache.load().map(\.memoryID), ["mem-new"])
    }
}
