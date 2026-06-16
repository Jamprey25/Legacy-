import XCTest
@testable import APIClient
import LegacyAPIStubs

final class APIClientTests: XCTestCase {

    private func makeConfig() -> LegacyAPIConfiguration {
        LegacyAPIConfiguration(
            baseURL: URL(string: "https://api.example.com")!,
            appVersion: "1.2.3",
            deviceID: "device-abc"
        )
    }

    func testConfigurationStoresValues() {
        let config = makeConfig()
        XCTAssertEqual(config.baseURL.absoluteString, "https://api.example.com")
        XCTAssertEqual(config.appVersion, "1.2.3")
        XCTAssertEqual(config.deviceID, "device-abc")
    }

    // MARK: - Header injection

    func testAuthenticatedRequestInjectsContractHeaders() throws {
        let client = LegacyAPIClient(configuration: makeConfig(), tokenProvider: { "tok-123" })
        let req = LegacyRequest(method: .post, path: "/v1/discovery/scan", body: Data("{}".utf8))

        let urlRequest = try client.makeURLRequest(req)

        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-App-Version"), "1.2.3")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Device-Id"), "device-abc")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(urlRequest.value(forHTTPHeaderField: "X-Request-Timestamp"))
    }

    func testMissingTokenThrowsUnauthorizedBeforeNetwork() {
        let client = LegacyAPIClient(configuration: makeConfig(), tokenProvider: { nil })
        let req = LegacyRequest(method: .get, path: "/v1/memories/x")

        XCTAssertThrowsError(try client.makeURLRequest(req)) { error in
            guard case LegacyAPIError.unauthorized(let code) = error else {
                return XCTFail("expected unauthorized, got \(error)")
            }
            XCTAssertEqual(code, "no_token")
        }
    }

    func testUnauthenticatedRequestOmitsAuthorization() throws {
        let client = LegacyAPIClient(configuration: makeConfig(), tokenProvider: { nil })
        let req = LegacyRequest(method: .post, path: "/v1/auth/social", body: Data("{}".utf8), requiresAuth: false)

        let urlRequest = try client.makeURLRequest(req)
        XCTAssertNil(urlRequest.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - Status mapping

    func testValidate401MapsToUnauthorizedWithCode() {
        let body = Data(#"{"error":{"code":"token_expired","message":"expired"}}"#.utf8)
        XCTAssertThrowsError(try LegacyAPIClient.validate(status: 401, data: body, headers: response(401))) { error in
            guard case LegacyAPIError.unauthorized(let code) = error else {
                return XCTFail("expected unauthorized, got \(error)")
            }
            XCTAssertEqual(code, "token_expired")
        }
    }

    func testValidate423MapsToLockedWithDwellInfo() {
        let body = Data(#"{"error":{"code":"dwell_required","message":"stay"},"retry_after_s":20}"#.utf8)
        XCTAssertThrowsError(try LegacyAPIClient.validate(status: 423, data: body, headers: response(423))) { error in
            guard case LegacyAPIError.locked(let code, _, let info) = error else {
                return XCTFail("expected locked, got \(error)")
            }
            XCTAssertEqual(code, "dwell_required")
            XCTAssertEqual(info.retryAfterSeconds, 20)
        }
    }

    func testValidate2xxDoesNotThrow() {
        XCTAssertNoThrow(try LegacyAPIClient.validate(status: 200, data: Data(), headers: response(200)))
        XCTAssertNoThrow(try LegacyAPIClient.validate(status: 204, data: Data(), headers: response(204)))
    }

    // MARK: - End-to-end via stub transport

    func testScanReturnsNilOn204() async throws {
        let transport = StubHTTPTransport()
        transport.enqueue("/v1/discovery/scan", .noContent)
        let client = LegacyAPIClient(configuration: makeConfig(), transport: transport, tokenProvider: { "t" })

        let result = try await client.scan(LocationRequest(lat: 1, lng: 2, accuracyM: 8))
        XCTAssertNil(result)
    }

    func testScanDecodesTeasersFromFixture() async throws {
        let client = LegacyAPIClient.stubbed()
        let result = try await client.scan(LocationRequest(lat: 1, lng: 2, accuracyM: 8))
        XCTAssertEqual(result?.teasers.count, 1)
        XCTAssertEqual(result?.teasers.first?.warmth, "in_bubble")
        XCTAssertEqual(result?.teasers.first?.isOwn, true)
    }

    func testHappyPathUnlockModelsDwellThenSuccess() async throws {
        let client = LegacyAPIClient.stubbed()
        let body = LocationRequest(lat: 1, lng: 2, accuracyM: 8)

        // First unlock attempt: dwell required (423).
        do {
            _ = try await client.unlock(memoryID: "m1", body)
            XCTFail("expected dwell lock on first attempt")
        } catch let LegacyAPIError.locked(code, _, info) {
            XCTAssertEqual(code, "dwell_required")
            XCTAssertEqual(info.retryAfterSeconds, 20)
        }

        // Second attempt: unlocked.
        let unlocked = try await client.unlock(memoryID: "m1", body)
        XCTAssertEqual(unlocked.returnCount, 3)
        XCTAssertEqual(unlocked.media.first?.type, "photo")
    }

    func testFixturesDecodeAgainstContractModels() throws {
        XCTAssertNoThrow(try LegacyFixtures.validateAll())
    }

    // MARK: - Helpers

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
