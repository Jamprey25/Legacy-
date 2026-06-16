import XCTest
@testable import APIClient

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

    // MARK: - End-to-end via mock transport

    func testScanReturnsNilOn204() async throws {
        let transport = MockTransport(status: 204, body: Data())
        let client = LegacyAPIClient(configuration: makeConfig(), transport: transport, tokenProvider: { "t" })

        let result = try await client.scan(LocationRequest(lat: 1, lng: 2, accuracyM: 8))
        XCTAssertNil(result)
    }

    func testScanDecodesTeasers() async throws {
        let json = #"{"teasers":[{"memory_id":"m1","thumbnail_url":null,"drop_date":"2024-09-01","owner_display":"you","is_own":true,"in_range":true,"warmth":"in_bubble","scan_status":"clear"}]}"#
        let transport = MockTransport(status: 200, body: Data(json.utf8))
        let client = LegacyAPIClient(configuration: makeConfig(), transport: transport, tokenProvider: { "t" })

        let result = try await client.scan(LocationRequest(lat: 1, lng: 2, accuracyM: 8))
        XCTAssertEqual(result?.teasers.count, 1)
        XCTAssertEqual(result?.teasers.first?.warmth, "in_bubble")
        XCTAssertEqual(result?.teasers.first?.isOwn, true)
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

private struct MockTransport: HTTPTransport {
    let status: Int
    let body: Data

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
