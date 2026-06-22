import APIClient
import Foundation

/// Joseph decided 100m reveal vs ~20m unlock (dec-pin-reveal-radius, 2026-06-22).
public enum PinRevealPolicy {
    public static let revealRadiusMeters = 100.0

    /// Others' memory pins the server exposes once the user is within reveal radius.
    public static func revealedOthers(from teasers: [Teaser]) -> [RevealedMemoryPin] {
        teasers.compactMap { teaser in
            guard !teaser.isOwn, teaser.pinRevealed, let lat = teaser.lat, let lng = teaser.lng else {
                return nil
            }
            return RevealedMemoryPin(
                memoryID: teaser.memoryID,
                lat: lat,
                lng: lng,
                thumbnailURL: teaser.thumbnailURL
            )
        }
    }
}

public struct RevealedMemoryPin: Sendable, Equatable, Identifiable {
    public let memoryID: String
    public let lat: Double
    public let lng: Double
    public let thumbnailURL: String?

    public var id: String { memoryID }
}
