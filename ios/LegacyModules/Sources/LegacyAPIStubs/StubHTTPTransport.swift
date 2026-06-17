import APIClient
import Foundation

/// A canned HTTP response for the stub transport.
public struct StubResponse: Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    public static func ok(_ body: Data) -> StubResponse { .init(statusCode: 200, body: body) }
    public static func json(_ statusCode: Int, _ body: Data) -> StubResponse { .init(statusCode: statusCode, body: body) }
    public static let noContent = StubResponse(statusCode: 204, body: Data())
}

/// An offline `HTTPTransport` that serves canned responses keyed by path suffix.
///
/// Drives SwiftUI previews, GPX-based UI tests, and unit tests with zero network.
/// Per-route responses are a queue: enqueue `[423, 200]` to model the dwell flow
/// (first call locked, second call unlocks). The last response repeats once drained.
public final class StubHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: [StubResponse]]
    private let fallback: StubResponse

    public init(
        routes: [String: [StubResponse]] = [:],
        fallback: StubResponse = StubResponse(statusCode: 404, body: Data())
    ) {
        self.routes = routes
        self.fallback = fallback
    }

    /// Queue one or more responses for requests whose path ends with `path`.
    /// Prefix with `"GET "` or `"POST "` to match HTTP method + path (e.g. `"GET /v1/memories"`).
    public func enqueue(_ path: String, _ responses: StubResponse...) {
        lock.lock(); defer { lock.unlock() }
        routes[path, default: []].append(contentsOf: responses)
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        let chosen: StubResponse = {
            lock.lock(); defer { lock.unlock() }
            guard let key = routes.keys.first(where: { routeKey in
                if routeKey.contains(" ") {
                    let parts = routeKey.split(separator: " ", maxSplits: 1)
                    guard parts.count == 2 else { return false }
                    return parts[0] == Substring(method) && path.hasSuffix(String(parts[1]))
                }
                return path.hasSuffix(routeKey)
            }) else {
                return fallback
            }
            var queue = routes[key] ?? []
            let next = queue.isEmpty ? fallback : (queue.count == 1 ? queue[0] : queue.removeFirst())
            routes[key] = queue
            return next
        }()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stub.legacy.app")!,
            statusCode: chosen.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (chosen.body, response)
    }
}
