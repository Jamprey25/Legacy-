import Foundation

public struct LegacyAPIConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let appVersion: String
    /// Stable per-install UUID. Sent as `X-Device-Id` (contract §1.1).
    public let deviceID: String

    public init(baseURL: URL, appVersion: String, deviceID: String) {
        self.baseURL = baseURL
        self.appVersion = appVersion
        self.deviceID = deviceID
    }
}

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

/// A typed, contract-shaped request prior to URL/header materialization.
public struct LegacyRequest: Sendable {
    public let method: HTTPMethod
    /// Path under the base URL, including the `/v1` prefix (e.g. `/v1/discovery/scan`).
    public let path: String
    public let body: Data?
    public let requiresAuth: Bool

    public init(method: HTTPMethod, path: String, body: Data? = nil, requiresAuth: Bool = true) {
        self.method = method
        self.path = path
        self.body = body
        self.requiresAuth = requiresAuth
    }
}

/// Minimal seam over URLSession so the client is testable without the network.
public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

public protocol LegacyAPIClientProtocol: Sendable {
    var configuration: LegacyAPIConfiguration { get }
    func send<Response: Decodable>(_ request: LegacyRequest, as type: Response.Type) async throws -> Response
    /// For endpoints that may return `204` (e.g. `/discovery/scan`): `nil` on 204.
    func sendOptional<Response: Decodable>(_ request: LegacyRequest, as type: Response.Type) async throws -> Response?
    /// For endpoints with no response body.
    func sendNoContent(_ request: LegacyRequest) async throws
}

public struct LegacyAPIClient: LegacyAPIClientProtocol {
    public let configuration: LegacyAPIConfiguration

    private let transport: HTTPTransport
    /// Reads the session token from the Keychain on each request. Injectable for tests.
    private let tokenProvider: @Sendable () -> String?

    public init(
        configuration: LegacyAPIConfiguration,
        transport: HTTPTransport = URLSession.shared,
        tokenProvider: @escaping @Sendable () -> String? = { try? KeychainSessionStore.read() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenProvider = tokenProvider
    }

    // MARK: - Public send variants

    public func send<Response: Decodable>(_ request: LegacyRequest, as type: Response.Type) async throws -> Response {
        let (data, _) = try await perform(request, allowEmpty: false)
        return try decode(data, as: Response.self)
    }

    public func sendOptional<Response: Decodable>(_ request: LegacyRequest, as type: Response.Type) async throws -> Response? {
        let (data, status) = try await perform(request, allowEmpty: true)
        if status == 204 || data.isEmpty { return nil }
        return try decode(data, as: Response.self)
    }

    public func sendNoContent(_ request: LegacyRequest) async throws {
        _ = try await perform(request, allowEmpty: true)
    }

    // MARK: - Core

    private func perform(_ request: LegacyRequest, allowEmpty: Bool) async throws -> (Data, Int) {
        let urlRequest = try makeURLRequest(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: urlRequest)
        } catch {
            throw LegacyAPIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LegacyAPIError.invalidResponse(statusCode: -1)
        }

        try Self.validate(status: http.statusCode, data: data, headers: http)
        return (data, http.statusCode)
    }

    func makeURLRequest(_ request: LegacyRequest) throws -> URLRequest {
        guard let url = URL(string: request.path, relativeTo: configuration.baseURL) else {
            throw LegacyAPIError.invalidRequest(code: "invalid_path", message: "Bad request path.")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(configuration.appVersion, forHTTPHeaderField: "X-App-Version")
        urlRequest.setValue(configuration.deviceID, forHTTPHeaderField: "X-Device-Id")
        urlRequest.setValue(Self.timestampFormatter.string(from: Date()), forHTTPHeaderField: "X-Request-Timestamp")

        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if request.requiresAuth {
            guard let token = tokenProvider() else {
                throw LegacyAPIError.unauthorized(code: "no_token")
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return urlRequest
    }

    // MARK: - Binary media upload

    /// Server-side blob upload: POST the (EXIF-stripped) bytes to `/v1/uploads/direct`.
    /// The backend stores them via the official @vercel/blob `put()` and flips scan_status.
    /// Returns the stored public blob URL.
    public func uploadMemoryMediaDirect(
        memoryID: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        guard let url = URL(string: "/v1/uploads/direct", relativeTo: configuration.baseURL) else {
            throw LegacyAPIError.invalidRequest(code: "invalid_path", message: "Bad upload path.")
        }
        guard let token = tokenProvider() else {
            throw LegacyAPIError.unauthorized(code: "no_token")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue(memoryID, forHTTPHeaderField: "X-Memory-Id")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(configuration.appVersion, forHTTPHeaderField: "X-App-Version")
        req.setValue(configuration.deviceID, forHTTPHeaderField: "X-Device-Id")
        req.setValue(Self.timestampFormatter.string(from: Date()), forHTTPHeaderField: "X-Request-Timestamp")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: req)
        } catch {
            throw LegacyAPIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw LegacyAPIError.invalidResponse(statusCode: -1)
        }
        try Self.validate(status: http.statusCode, data: data, headers: http)
        return try decode(data, as: DirectUploadResponse.self).url
    }

    private struct DirectUploadResponse: Decodable { let url: String }

    // MARK: - Status validation

    static func validate(status: Int, data: Data, headers: HTTPURLResponse) throws {
        switch status {
        case 200...299:
            return
        case 401:
            throw LegacyAPIError.unauthorized(code: errorCode(in: data) ?? "unauthorized")
        case 403:
            let env = envelope(in: data)
            throw LegacyAPIError.forbidden(code: env?.code ?? "forbidden", message: env?.message ?? "")
        case 404:
            throw LegacyAPIError.notFound
        case 409:
            let env = envelope(in: data)
            throw LegacyAPIError.conflict(code: env?.code ?? "conflict", message: env?.message ?? "")
        case 423:
            let env = envelope(in: data)
            throw LegacyAPIError.locked(
                code: env?.code ?? "locked",
                message: env?.message ?? "",
                info: lockedInfo(in: data)
            )
        case 429:
            let retryAfter = headers.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw LegacyAPIError.rateLimited(retryAfter: retryAfter)
        case 400, 422:
            let env = envelope(in: data)
            throw LegacyAPIError.invalidRequest(code: env?.code ?? "invalid_request", message: env?.message ?? "")
        case 500...599:
            throw LegacyAPIError.server(statusCode: status)
        default:
            throw LegacyAPIError.invalidResponse(statusCode: status)
        }
    }

    // MARK: - Decoding helpers

    private func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T {
        do {
            return try Self.jsonDecoder.decode(T.self, from: data)
        } catch {
            throw LegacyAPIError.decoding
        }
    }

    private static func envelope(in data: Data) -> APIErrorEnvelope.Body? {
        try? jsonDecoder.decode(APIErrorEnvelope.self, from: data).error
    }

    private static func errorCode(in data: Data) -> String? {
        envelope(in: data)?.code
    }

    private static func lockedInfo(in data: Data) -> LockedInfo {
        guard let body = try? jsonDecoder.decode(LockedBody.self, from: data) else { return .empty }
        return LockedInfo(
            retryAfterSeconds: body.retryAfterS,
            opensAt: body.opensAt.flatMap { timestampFormatter.date(from: $0) },
            fallbackAt: body.fallbackAt.flatMap { timestampFormatter.date(from: $0) }
        )
    }

    // MARK: - Shared formatters

    /// RFC 3339 / ISO 8601 UTC. Used for `X-Request-Timestamp` and timestamp parsing.
    static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let jsonDecoder = JSONDecoder()
    static let jsonEncoder = JSONEncoder()
}
