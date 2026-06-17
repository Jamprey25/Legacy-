import Foundation

// Typed request/response models + endpoint methods, coding to `api-contract.md`.
// Timestamps are kept as ISO-8601 strings to avoid a single global date-decoding
// strategy clashing with the contract's mix of date-only and full-timestamp fields.

// MARK: - Auth (§2)

public struct DeviceInfo: Encodable, Sendable {
    public let deviceID: String
    public let model: String?
    public let osVersion: String?

    public init(deviceID: String, model: String? = nil, osVersion: String? = nil) {
        self.deviceID = deviceID
        self.model = model
        self.osVersion = osVersion
    }

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case model
        case osVersion = "os_version"
    }
}

public struct SocialAuthRequest: Encodable, Sendable {
    public let provider: String          // "apple" | "google"
    public let identityToken: String
    public let dob: String?              // required on FIRST sign-in only
    public let device: DeviceInfo

    public init(provider: String, identityToken: String, dob: String?, device: DeviceInfo) {
        self.provider = provider
        self.identityToken = identityToken
        self.dob = dob
        self.device = device
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case identityToken = "identity_token"
        case dob, device
    }
}

public struct AuthUser: Decodable, Sendable, Equatable {
    public let id: String
    public let ageTier: String           // "adult" | "minor"
    public let isNew: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case ageTier = "age_tier"
        case isNew = "is_new"
    }
}

public struct AuthResponse: Decodable, Sendable, Equatable {
    public let sessionToken: String
    public let expiresAt: String
    public let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case sessionToken = "session_token"
        case expiresAt = "expires_at"
        case user
    }
}

public struct EmailStartRequest: Encodable, Sendable {
    public let email: String

    public init(email: String) {
        self.email = email
    }
}

public struct EmailVerifyRequest: Encodable, Sendable {
    public let email: String
    public let code: String
    public let dob: String?
    public let device: DeviceInfo

    public init(email: String, code: String, dob: String?, device: DeviceInfo) {
        self.email = email
        self.code = code
        self.dob = dob
        self.device = device
    }
}

// MARK: - Memory creation (§3)

public struct CreateMemoryRequest: Encodable, Sendable {
    public let lat: Double
    public let lng: Double
    public let accuracyM: Double
    public let mediaType: String         // "photo" | "text"
    public let dropMethod: String        // "pin" | "treasure_chest" | "note_bottle"
    public let privacyTier: String       // Phase 1: "private"
    public let teaserText: String?
    public let cooldownHours: Int?
    public let attestation: String?

    public init(
        lat: Double,
        lng: Double,
        accuracyM: Double,
        mediaType: String,
        dropMethod: String,
        privacyTier: String = "private",
        teaserText: String? = nil,
        cooldownHours: Int? = 24,
        attestation: String? = nil
    ) {
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.mediaType = mediaType
        self.dropMethod = dropMethod
        self.privacyTier = privacyTier
        self.teaserText = teaserText
        self.cooldownHours = cooldownHours
        self.attestation = attestation
    }

    enum CodingKeys: String, CodingKey {
        case lat, lng
        case accuracyM = "accuracy_m"
        case mediaType = "media_type"
        case dropMethod = "drop_method"
        case privacyTier = "privacy_tier"
        case teaserText = "teaser_text"
        case cooldownHours = "cooldown_hours"
        case attestation
    }
}

public struct SignedUpload: Decodable, Sendable, Equatable {
    public let signedPutURL: String
    public let expiresAt: String
    public let method: String
    public let headers: [String: String]

    enum CodingKeys: String, CodingKey {
        case signedPutURL = "signed_put_url"
        case expiresAt = "expires_at"
        case method, headers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signedPutURL = try container.decode(String.self, forKey: .signedPutURL)
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt) ?? ""
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "PUT"
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers)
            ?? ["Content-Type": "image/jpeg"]
    }

    public init(signedPutURL: String, expiresAt: String, method: String, headers: [String: String]) {
        self.signedPutURL = signedPutURL
        self.expiresAt = expiresAt
        self.method = method
        self.headers = headers
    }
}

public struct CreateMemoryResponse: Decodable, Sendable, Equatable {
    public let memoryID: String
    public let upload: SignedUpload?
    public let discoverableAfter: String
    public let scanStatus: String

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case upload
        case discoverableAfter = "discoverable_after"
        case scanStatus = "scan_status"
        case signedPutURLFlat = "signed_put_url"
        case expiresAtFlat = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memoryID = try container.decode(String.self, forKey: .memoryID)
        discoverableAfter = try container.decodeIfPresent(String.self, forKey: .discoverableAfter) ?? ""
        scanStatus = try container.decodeIfPresent(String.self, forKey: .scanStatus) ?? "pending"

        if let nested = try container.decodeIfPresent(SignedUpload.self, forKey: .upload) {
            upload = nested
        } else if let flatURL = try container.decodeIfPresent(String.self, forKey: .signedPutURLFlat) {
            let expires = try container.decodeIfPresent(String.self, forKey: .expiresAtFlat) ?? ""
            upload = SignedUpload(
                signedPutURL: flatURL,
                expiresAt: expires,
                method: "PUT",
                headers: ["Content-Type": "image/jpeg"]
            )
        } else {
            upload = nil
        }
    }
}

// MARK: - Memory Lane (owner list)

public struct MemoryLaneItem: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String { memoryID }
    public let memoryID: String
    public let dropDate: String
    public let createdAt: String
    public let mediaType: String
    public let scanStatus: String
    public let thumbnailKey: String?
    public let privacyTier: String
    public let dropMethod: String

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case dropDate = "drop_date"
        case createdAt = "created_at"
        case mediaType = "media_type"
        case scanStatus = "scan_status"
        case thumbnailKey = "thumbnail_key"
        case privacyTier = "privacy_tier"
        case dropMethod = "drop_method"
    }
}

public struct ListMemoriesResponse: Decodable, Sendable, Equatable {
    public let memories: [MemoryLaneItem]
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case memories
        case nextCursor = "next_cursor"
    }
}

/// Owner-only full memory row (`GET /v1/memories/{id}`). Includes coordinates — owner only.
public struct MemoryDetail: Decodable, Sendable, Equatable {
    public let memoryID: String
    public let lat: Double
    public let lng: Double
    public let geohash: String
    public let source: String
    public let dropMethod: String
    public let privacyTier: String
    public let scanStatus: String
    public let mediaType: String
    public let mediaKey: String?
    public let thumbnailKey: String?
    public let discoverableAfter: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case lat, lng, geohash, source
        case dropMethod = "drop_method"
        case privacyTier = "privacy_tier"
        case scanStatus = "scan_status"
        case mediaType = "media_type"
        case mediaKey = "media_key"
        case thumbnailKey = "thumbnail_key"
        case discoverableAfter = "discoverable_after"
        case createdAt = "created_at"
    }
}

// MARK: - Discovery (§4)

public struct LocationRequest: Encodable, Sendable {
    public let lat: Double
    public let lng: Double
    public let accuracyM: Double
    public let attestation: String?

    public init(lat: Double, lng: Double, accuracyM: Double, attestation: String? = nil) {
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.attestation = attestation
    }

    enum CodingKeys: String, CodingKey {
        case lat, lng
        case accuracyM = "accuracy_m"
        case attestation
    }
}

public struct Teaser: Decodable, Sendable, Equatable {
    public let memoryID: String
    public let thumbnailURL: String?
    public let dropDate: String
    public let ownerDisplay: String
    public let isOwn: Bool
    public let inRange: Bool
    /// Non-directional warmth — the only proximity signal (DEC-15). No bearing field exists.
    public let warmth: String
    public let scanStatus: String

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case thumbnailURL = "thumbnail_url"
        case dropDate = "drop_date"
        case ownerDisplay = "owner_display"
        case isOwn = "is_own"
        case inRange = "in_range"
        case warmth
        case scanStatus = "scan_status"
    }
}

public struct ScanResponse: Decodable, Sendable, Equatable {
    public let teasers: [Teaser]
}

public struct UnlockedMedia: Decodable, Sendable, Equatable {
    public let url: String
    public let type: String
    public let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case url, type
        case expiresAt = "expires_at"
    }
}

public struct UnlockResponse: Decodable, Sendable, Equatable {
    public let memoryID: String
    public let media: [UnlockedMedia]
    public let caption: String?
    public let dropDate: String
    public let ownerDisplay: String
    public let findRecorded: Bool
    public let returnCount: Int

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case media, caption
        case dropDate = "drop_date"
        case ownerDisplay = "owner_display"
        case findRecorded = "find_recorded"
        case returnCount = "return_count"
    }
}

// MARK: - Endpoint methods

extension LegacyAPIClient {
    public func authSocial(_ body: SocialAuthRequest) async throws -> AuthResponse {
        try await send(request(.post, "/v1/auth/social", body, requiresAuth: false), as: AuthResponse.self)
    }

    public func authEmailStart(_ email: String) async throws {
        try await sendNoContent(
            try request(.post, "/v1/auth/email/start", EmailStartRequest(email: email), requiresAuth: false)
        )
    }

    public func authEmailVerify(_ body: EmailVerifyRequest) async throws -> AuthResponse {
        try await send(request(.post, "/v1/auth/email/verify", body, requiresAuth: false), as: AuthResponse.self)
    }

    public func createMemory(_ body: CreateMemoryRequest) async throws -> CreateMemoryResponse {
        try await send(request(.post, "/v1/memories", body), as: CreateMemoryResponse.self)
    }

    /// Paginated owner list for Memory Lane — oldest first, no coordinates.
    public func listMemories(cursor: String? = nil, limit: Int = 50) async throws -> ListMemoriesResponse {
        var path = "/v1/memories?limit=\(limit)"
        if let cursor, !cursor.isEmpty {
            let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cursor
            path += "&cursor=\(encoded)"
        }
        return try await send(LegacyRequest(method: .get, path: path), as: ListMemoriesResponse.self)
    }

    /// Owner-only detail including drop coordinates.
    public func getMemory(id: String) async throws -> MemoryDetail {
        try await send(LegacyRequest(method: .get, path: "/v1/memories/\(id)"), as: MemoryDetail.self)
    }

    /// Batch-create private memories from on-device clusters (contract §5).
    public func importMemories(_ body: ImportMemoriesRequest) async throws -> ImportMemoriesResponse {
        try await send(request(.post, "/v1/memories/import", body), as: ImportMemoriesResponse.self)
    }

    /// Returns `nil` when the server responds `204` (nothing eligible nearby).
    public func scan(_ body: LocationRequest) async throws -> ScanResponse? {
        try await sendOptional(request(.post, "/v1/discovery/scan", body), as: ScanResponse.self)
    }

    public func unlock(memoryID: String, _ body: LocationRequest) async throws -> UnlockResponse {
        try await send(request(.post, "/v1/memories/\(memoryID)/unlock", body), as: UnlockResponse.self)
    }

    public func logout() async throws {
        try await sendNoContent(LegacyRequest(method: .post, path: "/v1/auth/logout", body: Data("{}".utf8)))
    }

    /// Notify the backend that an upload completed so it can run the CSAM pipeline stub.
    /// Only called in DEBUG builds — in production the storage provider fires this webhook
    /// server-to-server and the app is never involved.
    /// Requires WEBHOOK_SECRET=dev-webhook-secret in the backend .env.local.
    #if DEBUG
    public func notifyUploadComplete(memoryID: String, mediaKey: String) async throws {
        struct Body: Encodable { let memory_id: String; let media_key: String }
        let bodyData = try Self.jsonEncoder.encode(Body(memory_id: memoryID, media_key: mediaKey))
        let url = configuration.baseURL.appendingPathComponent("v1/internal/webhook/storage")
        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.httpBody = bodyData
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.setValue("dev-webhook-secret", forHTTPHeaderField: "X-Webhook-Secret")
        _ = try? await URLSession.shared.data(for: urlReq)
    }
    #endif

    // MARK: Request building helper

    private func request<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        _ body: Body,
        requiresAuth: Bool = true
    ) throws -> LegacyRequest {
        let data: Data
        do {
            data = try Self.jsonEncoder.encode(body)
        } catch {
            throw LegacyAPIError.invalidRequest(code: "encoding_failed", message: "Could not encode request body.")
        }
        return LegacyRequest(method: method, path: path, body: data, requiresAuth: requiresAuth)
    }
}
