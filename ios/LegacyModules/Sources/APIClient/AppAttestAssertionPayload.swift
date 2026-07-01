import Foundation

/// Assertion + challenge pair for sensitive API requests (SEC-P2-8).
public struct AppAttestAssertionPayload: Sendable, Equatable {
    public let attestation: String
    public let challengeToken: String

    public init(attestation: String, challengeToken: String) {
        self.attestation = attestation
        self.challengeToken = challengeToken
    }
}
