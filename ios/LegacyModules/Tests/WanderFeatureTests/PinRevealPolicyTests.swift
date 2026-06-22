import APIClient
import WanderFeature
import XCTest

final class PinRevealPolicyTests: XCTestCase {
    func testRevealedOthersRequiresPinRevealedAndCoords() {
        let revealed = Teaser(
            memoryID: "a",
            thumbnailURL: nil,
            dropDate: "2024-01-01",
            ownerDisplay: "unknown",
            isOwn: false,
            inRange: false,
            warmth: "approaching",
            scanStatus: "clear",
            pinRevealed: true,
            lat: 1,
            lng: 2
        )
        let hidden = Teaser(
            memoryID: "b",
            thumbnailURL: nil,
            dropDate: "2024-01-01",
            ownerDisplay: "unknown",
            isOwn: false,
            inRange: false,
            warmth: "coarse",
            scanStatus: "clear"
        )
        let own = Teaser(
            memoryID: "c",
            thumbnailURL: nil,
            dropDate: "2024-01-01",
            ownerDisplay: "you",
            isOwn: true,
            inRange: true,
            warmth: "in_bubble",
            scanStatus: "clear",
            pinRevealed: true,
            lat: 3,
            lng: 4
        )

        let pins = PinRevealPolicy.revealedOthers(from: [revealed, hidden, own])
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(pins.first?.memoryID, "a")
    }

    func testRevealRadiusConstantIs100m() {
        XCTAssertEqual(PinRevealPolicy.revealRadiusMeters, 100)
    }
}
