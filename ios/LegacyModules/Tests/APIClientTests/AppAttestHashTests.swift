import APIClient
import XCTest

final class AppAttestHashTests: XCTestCase {
    func testClientDataHashUsesRandomPrefixBeforeDot() throws {
        let token = "aabbcc00112233445566778899aabbcc00112233445566778899.cafebabe"
        let hash = try AppAttestChallenge.clientDataHash(for: token)
        XCTAssertEqual(hash.count, 32)

        let again = try AppAttestChallenge.clientDataHash(for: token)
        XCTAssertEqual(hash, again)
    }

    func testClientDataHashRejectsMalformedToken() {
        XCTAssertThrowsError(try AppAttestChallenge.clientDataHash(for: "no-dot-token"))
    }
}
