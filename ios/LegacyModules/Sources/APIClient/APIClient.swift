import Foundation

/// Typed REST wrapper over Legacy API endpoints.
/// Session token is read from Keychain — never UserDefaults or disk.
public struct LegacyAPIConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let appVersion: String

    public init(baseURL: URL, appVersion: String) {
        self.baseURL = baseURL
        self.appVersion = appVersion
    }
}

public enum LegacyAPIError: Error, Sendable, Equatable {
    case unauthorized
    case locked(reason: String)
    case serverError(statusCode: Int)
    case decodingFailed
    case invalidResponse
    case network(String)
}

/// Contract surface for HTTP operations. Endpoint methods added when `api-contract.md` lands.
public protocol LegacyAPIClientProtocol: Sendable {
    var configuration: LegacyAPIConfiguration { get }
}

public struct LegacyAPIClient: LegacyAPIClientProtocol {
    public let configuration: LegacyAPIConfiguration

    public init(configuration: LegacyAPIConfiguration) {
        self.configuration = configuration
    }
}
