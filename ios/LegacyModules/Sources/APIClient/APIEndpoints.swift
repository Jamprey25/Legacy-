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

public struct APNsTokenRequest: Encodable, Sendable {
    public let apnsToken: String

    public init(apnsToken: String) {
        self.apnsToken = apnsToken
    }

    enum CodingKeys: String, CodingKey {
        case apnsToken = "apns_token"
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
    public let caption: String?
    public let seal: MemorySealPayload?
    public let condition: MemoryConditionPayload?
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
        caption: String? = nil,
        seal: MemorySealPayload? = nil,
        condition: MemoryConditionPayload? = nil,
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
        self.caption = caption
        self.seal = seal
        self.condition = condition
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
        case caption
        case seal
        case condition
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

/// Memory Lane list sort order (maps to the backend `sort` query param).
public enum MemorySort: String, Sendable, CaseIterable {
    case oldest
    case newest

    public var label: String {
        switch self {
        case .oldest: return "Oldest first"
        case .newest: return "Newest first"
        }
    }
}

/// Optional Memory Lane list filter (`media_type` query param). `all` omits the param.
public enum MemoryMediaTypeFilter: String, Sendable, CaseIterable {
    case all
    case photo
    case video
    case text

    public var queryValue: String? {
        self == .all ? nil : rawValue
    }

    public var label: String {
        switch self {
        case .all: return "All types"
        case .photo: return "Photos"
        case .video: return "Videos"
        case .text: return "Notes"
        }
    }
}

public struct MemoryLaneItem: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String { memoryID }
    public let memoryID: String
    public let dropDate: String
    public let createdAt: String
    public let mediaType: String
    public let scanStatus: String
    public let thumbnailURL: String?
    /// Full-resolution own media. Present (when clear) so the grid can show the real
    /// image even when no server thumbnail exists — render `thumbnailURL ?? mediaURL`.
    public let mediaURL: String?
    public let caption: String?
    public let teaserText: String?
    public let privacyTier: String
    public let dropMethod: String
    /// Cleared photos in this memory. Optional — older servers omit it (treated as 1).
    public let photoCount: Int?

    /// A short label to disambiguate items in a dense grid (caption preferred, else teaser).
    public var displayLabel: String? {
        if let caption, !caption.isEmpty { return caption }
        if let teaserText, !teaserText.isEmpty { return teaserText }
        return nil
    }

    /// Grid preview: prefer thumbnail, fall back to full-res own media when clear.
    public var previewImageURL: String? {
        guard scanStatus == "clear" else { return nil }
        return thumbnailURL ?? mediaURL
    }

    /// True when the memory has more than one photo — drives the grid count badge.
    public var isMultiPhoto: Bool { (photoCount ?? 1) > 1 }

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case dropDate = "drop_date"
        case createdAt = "created_at"
        case mediaType = "media_type"
        case scanStatus = "scan_status"
        case thumbnailURL = "thumbnail_url"
        case mediaURL = "media_url"
        case caption
        case teaserText = "teaser_text"
        case privacyTier = "privacy_tier"
        case dropMethod = "drop_method"
        case photoCount = "photo_count"
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

/// One photo of a memory's ordered set (`GET /v1/memories/{id}` → `media[]`). Hero = position 0.
public struct MemoryMediaItem: Decodable, Sendable, Equatable, Identifiable {
    public let url: String
    public let thumbnailURL: String?
    public let type: String
    public let position: Int

    public var id: Int { position }

    enum CodingKeys: String, CodingKey {
        case url, type, position
        case thumbnailURL = "thumbnail_url"
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
    public let mediaURL: String?
    public let thumbnailURL: String?
    /// Full ordered photo set (hero-first). Optional — older servers omit it; mediaURL is
    /// the hero for back-compat. Empty/absent until the upload pipeline clears each photo.
    public let media: [MemoryMediaItem]?
    public let discoverableAfter: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case lat, lng, geohash, source
        case dropMethod = "drop_method"
        case privacyTier = "privacy_tier"
        case scanStatus = "scan_status"
        case mediaType = "media_type"
        case mediaURL = "media_url"
        case thumbnailURL = "thumbnail_url"
        case media
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
    /// True when user is within reveal radius (~100m). Coordinates only present when true (others' memories).
    public let pinRevealed: Bool
    public let lat: Double?
    public let lng: Double?

    enum CodingKeys: String, CodingKey {
        case memoryID = "memory_id"
        case thumbnailURL = "thumbnail_url"
        case dropDate = "drop_date"
        case ownerDisplay = "owner_display"
        case isOwn = "is_own"
        case inRange = "in_range"
        case warmth
        case scanStatus = "scan_status"
        case pinRevealed = "pin_revealed"
        case lat, lng
    }

    public init(
        memoryID: String,
        thumbnailURL: String?,
        dropDate: String,
        ownerDisplay: String,
        isOwn: Bool,
        inRange: Bool,
        warmth: String,
        scanStatus: String,
        pinRevealed: Bool = false,
        lat: Double? = nil,
        lng: Double? = nil
    ) {
        self.memoryID = memoryID
        self.thumbnailURL = thumbnailURL
        self.dropDate = dropDate
        self.ownerDisplay = ownerDisplay
        self.isOwn = isOwn
        self.inRange = inRange
        self.warmth = warmth
        self.scanStatus = scanStatus
        self.pinRevealed = pinRevealed
        self.lat = lat
        self.lng = lng
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memoryID = try container.decode(String.self, forKey: .memoryID)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        dropDate = try container.decode(String.self, forKey: .dropDate)
        ownerDisplay = try container.decode(String.self, forKey: .ownerDisplay)
        isOwn = try container.decode(Bool.self, forKey: .isOwn)
        inRange = try container.decode(Bool.self, forKey: .inRange)
        warmth = try container.decode(String.self, forKey: .warmth)
        scanStatus = try container.decode(String.self, forKey: .scanStatus)
        pinRevealed = try container.decodeIfPresent(Bool.self, forKey: .pinRevealed) ?? false
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lng = try container.decodeIfPresent(Double.self, forKey: .lng)
    }
}

/// A precision-7 geohash cell (~150m) containing one or more others' memories.
/// No coordinates — only the cell prefix and count (DEC-15).
public struct CoarseZone: Decodable, Sendable, Equatable {
    public let geohashPrefix: String
    public let count: Int

    public init(geohashPrefix: String, count: Int) {
        self.geohashPrefix = geohashPrefix
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case geohashPrefix = "geohash_prefix"
        case count
    }
}

public struct ScanResponse: Decodable, Sendable, Equatable {
    public let teasers: [Teaser]
    /// Coarse zone cells for others' memories — render as glow overlays, never as pins.
    public let zones: [CoarseZone]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teasers = try container.decode([Teaser].self, forKey: .teasers)
        zones = try container.decodeIfPresent([CoarseZone].self, forKey: .zones) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case teasers, zones
    }
}

public struct UnlockedMedia: Decodable, Sendable, Equatable {
    public let url: String
    public let type: String
    public let expiresAt: String
    /// Order within the memory's photo set (hero = 0). Optional — older servers omit it.
    public let position: Int?

    enum CodingKeys: String, CodingKey {
        case url, type, position
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

// MARK: - Account (§7)

public struct PatchUserRequest: Encodable, Sendable {
    public let displayName: String?

    public init(displayName: String?) {
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

public struct PatchUserResponse: Decodable, Sendable, Equatable {
    public let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

// MARK: - Muted zones (§9)

public struct MutedZone: Decodable, Sendable, Identifiable, Equatable {
    public let id: String
    public let lat: Double
    public let lng: Double
    public let radiusM: Int
    public let label: String?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, lat, lng, label
        case radiusM = "radius_m"
        case createdAt = "created_at"
    }
}

public struct CreateMutedZoneRequest: Encodable, Sendable {
    public let lat: Double
    public let lng: Double
    public let radiusM: Int
    public let label: String?

    public init(lat: Double, lng: Double, radiusM: Int, label: String?) {
        self.lat = lat
        self.lng = lng
        self.radiusM = radiusM
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case lat, lng, label
        case radiusM = "radius_m"
    }
}

public struct MutedZonesResponse: Decodable, Sendable {
    public let zones: [MutedZone]
}

public struct CreateMutedZoneResponse: Decodable, Sendable {
    public let zone: MutedZone
}

public struct ExportResponse: Decodable, Sendable, Equatable {
    public let archiveURL: String
    public let memoryCount: Int
    public let exportedAt: String

    enum CodingKeys: String, CodingKey {
        case archiveURL = "archive_url"
        case memoryCount = "memory_count"
        case exportedAt = "exported_at"
    }
}

// MARK: - App Attest (§8 / M5)

public struct AttestChallengeResponse: Decodable, Sendable {
    public let challengeToken: String
    public let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case challengeToken = "challenge_token"
        case expiresAt = "expires_at"
    }
}

struct AttestRegisterRequest: Encodable, Sendable {
    let keyId: String
    let attestation: String
    let challengeToken: String

    enum CodingKeys: String, CodingKey {
        case keyId = "key_id"
        case attestation
        case challengeToken = "challenge_token"
    }
}

struct AttestRegisterResponse: Decodable, Sendable {
    let ok: Bool
    let environment: String?
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

    public func fetchAttestChallenge() async throws -> AttestChallengeResponse {
        try await send(
            LegacyRequest(method: .get, path: "/v1/auth/attest/challenge"),
            as: AttestChallengeResponse.self
        )
    }

    public func registerAppAttest(keyID: String, attestationBase64: String, challengeToken: String) async throws {
        _ = try await send(
            request(
                .post,
                "/v1/auth/attest/register",
                AttestRegisterRequest(
                    keyId: keyID,
                    attestation: attestationBase64,
                    challengeToken: challengeToken
                )
            ),
            as: AttestRegisterResponse.self
        )
    }

    public func createMemory(_ body: CreateMemoryRequest) async throws -> CreateMemoryResponse {
        try await send(request(.post, "/v1/memories", body), as: CreateMemoryResponse.self)
    }

    /// Vercel Blob handshake step 1 — scoped client token for direct upload (contract §3.2).
    public func generateBlobClientToken(memoryID: String, pathname: String) async throws -> String {
        let payload = BlobGenerateClientTokenRequest.Payload(
            pathname: pathname,
            multipart: false,
            clientPayload: "{\"memory_id\":\"\(memoryID)\"}"
        )
        let body = BlobGenerateClientTokenRequest(payload: payload)
        let response: BlobGenerateClientTokenResponse = try await send(
            request(.post, "/v1/uploads", body),
            as: BlobGenerateClientTokenResponse.self
        )
        guard response.clientToken.hasPrefix("vercel_blob_client_") else {
            throw BlobUploadError.invalidClientToken
        }
        return response.clientToken
    }

    /// Paginated owner list for Memory Lane — no coordinates.
    public func listMemories(
        cursor: String? = nil,
        limit: Int = 50,
        sort: MemorySort = .oldest,
        mediaType: MemoryMediaTypeFilter = .all
    ) async throws -> ListMemoriesResponse {
        var path = "/v1/memories?limit=\(limit)&sort=\(sort.rawValue)"
        if let mediaTypeValue = mediaType.queryValue {
            let encoded = mediaTypeValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mediaTypeValue
            path += "&media_type=\(encoded)"
        }
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

    /// Fetch all muted zones for the authenticated user.
    public func listMutedZones() async throws -> [MutedZone] {
        let response = try await send(LegacyRequest(method: .get, path: "/v1/user/muted-zones"), as: MutedZonesResponse.self)
        return response.zones
    }

    /// Create a new muted zone. Max 10 per user.
    public func createMutedZone(_ body: CreateMutedZoneRequest) async throws -> MutedZone {
        let response = try await send(request(.post, "/v1/user/muted-zones", body), as: CreateMutedZoneResponse.self)
        return response.zone
    }

    /// Delete a muted zone by ID.
    public func deleteMutedZone(id: String) async throws {
        try await sendNoContent(LegacyRequest(method: .delete, path: "/v1/user/muted-zones/\(id)"))
    }

    /// Update mutable profile fields (display_name). Pass nil display_name to clear.
    public func patchUser(_ body: PatchUserRequest) async throws -> PatchUserResponse {
        try await send(request(.patch, "/v1/user", body), as: PatchUserResponse.self)
    }

    /// Packages all own memories into a downloadable archive (contract §7).
    public func exportUserData() async throws -> ExportResponse {
        try await send(LegacyRequest(method: .get, path: "/v1/user/export"), as: ExportResponse.self)
    }

    /// Permanently deletes the account and all associated data (contract §7).
    public func deleteUser() async throws {
        try await sendNoContent(LegacyRequest(method: .delete, path: "/v1/user"))
    }

    /// Register or refresh the APNs device token for this install (contract §7 / M4).
    public func registerAPNsToken(_ body: APNsTokenRequest) async throws {
        try await sendNoContent(request(.post, "/v1/devices/apns", body))
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
