import XCTest
@testable import APIClient

final class CertificatePinningTests: XCTestCase {
    func testPinningEnabledForProductionAPIHost() {
        XCTAssertTrue(LegacyCertificatePinning.shouldPin(host: "legacy-backend-jamprey25s-projects.vercel.app"))
        XCTAssertFalse(LegacyCertificatePinning.shouldPin(host: "api.example.com"))
        XCTAssertFalse(LegacyCertificatePinning.shouldPin(host: "stub.legacy.app"))
    }
}
