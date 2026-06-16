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
}

public struct CreateMemoryResponse: Decodable, Sendable, Equatable {
    public let memoryID: String
    public let upload: SignedUpload?     // null for text memories
    public let discoverableAfter: String
    public let scanStatus: String

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case upload
        case discoverableAfter = "discoverable_after"
        case scanStatus = "scan_status"
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

    public func createMemory(_ body: CreateMemoryRequest) async throws -> CreateMemoryResponse {
        try await send(request(.post, "/v1/memories", body), as: CreateMemoryResponse.self)
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
