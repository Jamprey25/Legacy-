import XCTest
@testable import APIClient

final class APIClientTests: XCTestCase {
    func testConfigurationStoresBaseURL() {
        let url = URL(string: "https://api.example.com")!
        let config = LegacyAPIConfiguration(baseURL: url, appVersion: "1.0.0")
        XCTAssertEqual(config.baseURL, url)
        XCTAssertEqual(config.appVersion, "1.0.0")
    }
}
