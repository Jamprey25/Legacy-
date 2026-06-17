import APIClient
import Foundation

/// Contract-shaped JSON fixtures, kept in lockstep with `api-contract.md`.
///
/// These are the canonical example responses from the contract. `validateAll()` decodes
/// each into its `APIClient` model so a drift between the contract and the Swift `Codable`
/// shapes fails fast (use in CI / a unit test). When the backend ships an endpoint, diff a
/// live response against the matching fixture to catch server-side drift too.
public enum LegacyFixtures {

    public static let authSocial = Data("""
    {
      "session_token": "stub.jwt.token",
      "expires_at": "2026-07-16T20:55:00Z",
      "user": { "id": "11111111-1111-1111-1111-111111111111", "age_tier": "adult", "is_new": true }
    }
    """.utf8)

    public static let createMemory = Data("""
    {
      "memory_id": "22222222-2222-2222-2222-222222222222",
      "upload": {
        "signed_put_url": "https://s3.stub/key?sig=abc",
        "expires_at": "2026-06-16T21:10:00Z",
        "method": "PUT",
        "headers": { "Content-Type": "image/jpeg" }
      },
      "discoverable_after": "2026-06-17T20:55:00Z",
      "scan_status": "pending"
    }
    """.utf8)

    public static let scanWithTeasers = Data("""
    {
      "teasers": [
        {
          "memory_id": "22222222-2222-2222-2222-222222222222",
          "thumbnail_url": "https://s3.stub/thumb?sig=abc",
          "drop_date": "2024-09-01",
          "owner_display": "you",
          "is_own": true,
          "in_range": true,
          "warmth": "in_bubble",
          "scan_status": "clear"
        }
      ]
    }
    """.utf8)

    public static let unlock = Data("""
    {
      "memory_id": "22222222-2222-2222-2222-222222222222",
      "media": [
        { "url": "https://s3.stub/full?sig=abc", "type": "photo", "expires_at": "2026-06-16T21:55:00Z" }
      ],
      "caption": "First apartment.",
      "drop_date": "2024-09-01",
      "owner_display": "you",
      "find_recorded": true,
      "return_count": 3
    }
    """.utf8)

    public static let memoryList = Data("""
    {
      "memories": [
        {
          "memory_id": "22222222-2222-2222-2222-222222222222",
          "drop_date": "2024-09-01",
          "created_at": "2024-09-01T18:30:00Z",
          "media_type": "photo",
          "scan_status": "clear",
          "thumbnail_key": null,
          "privacy_tier": "private",
          "drop_method": "pin"
        },
        {
          "memory_id": "33333333-3333-3333-3333-333333333333",
          "drop_date": "2023-06-15",
          "created_at": "2023-06-15T12:00:00Z",
          "media_type": "photo",
          "scan_status": "pending",
          "thumbnail_key": null,
          "privacy_tier": "private",
          "drop_method": "pin"
        }
      ],
      "next_cursor": null
    }
    """.utf8)

    public static let memoryDetail = Data("""
    {
      "memory_id": "22222222-2222-2222-2222-222222222222",
      "lat": 37.7749,
      "lng": -122.4194,
      "geohash": "9q8yyk8yp",
      "source": "live",
      "drop_method": "pin",
      "privacy_tier": "private",
      "scan_status": "clear",
      "media_type": "photo",
      "media_key": "memories/22222222/full.jpg",
      "thumbnail_key": null,
      "discoverable_after": "2026-06-17T20:55:00Z",
      "created_at": "2024-09-01T18:30:00Z"
    }
    """.utf8)

    /// 423 Locked — dwell not yet satisfied (contract §4).
    public static let lockedDwell = Data("""
    {
      "error": { "code": "dwell_required", "message": "Stay here a moment longer to open this.", "request_id": "req_stub" },
      "retry_after_s": 20
    }
    """.utf8)

    /// Decodes every fixture into its model. Throws on the first contract/model mismatch.
    public static func validateAll(decoder: JSONDecoder = JSONDecoder()) throws {
        _ = try decoder.decode(AuthResponse.self, from: authSocial)
        _ = try decoder.decode(CreateMemoryResponse.self, from: createMemory)
        _ = try decoder.decode(ScanResponse.self, from: scanWithTeasers)
        _ = try decoder.decode(UnlockResponse.self, from: unlock)
        _ = try decoder.decode(ListMemoriesResponse.self, from: memoryList)
        _ = try decoder.decode(MemoryDetail.self, from: memoryDetail)
    }
}

extension StubHTTPTransport {
    /// A transport pre-wired with the happy-path fixtures plus a dwell-then-unlock
    /// sequence on `/unlock` (first call 423, second call 200) for the core loop.
    public static func happyPath() -> StubHTTPTransport {
        let transport = StubHTTPTransport()
        transport.enqueue("/v1/auth/social", .json(201, LegacyFixtures.authSocial))
        transport.enqueue("/v1/auth/email/start", .noContent)
        transport.enqueue("/v1/auth/email/verify", .json(201, LegacyFixtures.authSocial))
        transport.enqueue("POST /v1/memories", .json(201, LegacyFixtures.createMemory))
        transport.enqueue("GET /v1/memories", .ok(LegacyFixtures.memoryList))
        transport.enqueue("GET /memories/22222222-2222-2222-2222-222222222222", .ok(LegacyFixtures.memoryDetail))
        transport.enqueue("/v1/discovery/scan", .ok(LegacyFixtures.scanWithTeasers))
        transport.enqueue("/unlock", .json(423, LegacyFixtures.lockedDwell), .ok(LegacyFixtures.unlock))
        return transport
    }
}

extension LegacyAPIClient {
    /// A client wired to offline stubs — one-liner for SwiftUI previews and tests.
    public static func stubbed(
        transport: StubHTTPTransport = .happyPath(),
        token: String? = "stub-token"
    ) -> LegacyAPIClient {
        LegacyAPIClient(
            configuration: LegacyAPIConfiguration(
                baseURL: URL(string: "https://stub.legacy.app")!,
                appVersion: "0.1.0",
                deviceID: "preview-device"
            ),
            transport: transport,
            tokenProvider: { token }
        )
    }
}
