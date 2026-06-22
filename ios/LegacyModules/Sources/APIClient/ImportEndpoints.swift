import Foundation

public struct ImportClusterInput: Encodable, Sendable {
    public let lat: Double
    public let lng: Double
    public let capturedAt: String
    public let assetCount: Int
    /// How many photos the client will upload for this visit (the whole visit, not a cap).
    public let photoCount: Int

    enum CodingKeys: String, CodingKey {
        case lat, lng
        case capturedAt = "captured_at"
        case assetCount = "asset_count"
        case photoCount = "photo_count"
    }

    public init(lat: Double, lng: Double, capturedAt: String, assetCount: Int, photoCount: Int) {
        self.lat = lat
        self.lng = lng
        self.capturedAt = capturedAt
        self.assetCount = assetCount
        self.photoCount = photoCount
    }
}

public struct ImportMemoriesRequest: Encodable, Sendable {
    public let idempotencyKey: String
    public let clusters: [ImportClusterInput]

    enum CodingKeys: String, CodingKey {
        case idempotencyKey = "idempotency_key"
        case clusters
    }

    public init(idempotencyKey: String, clusters: [ImportClusterInput]) {
        self.idempotencyKey = idempotencyKey
        self.clusters = clusters
    }
}

public struct ImportedMemoryUpload: Decodable, Sendable, Equatable {
    public let signedPutURL: String
    public let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case signedPutURL = "signed_put_url"
        case expiresAt = "expires_at"
    }
}

public struct ImportedMemoryItem: Decodable, Sendable, Equatable {
    public let clusterIndex: Int
    public let memoryID: String
    /// Photos to upload for this memory (positions 0..mediaCount-1). Defaults to 1 for
    /// older servers that don't return it.
    public let mediaCount: Int
    public let upload: ImportedMemoryUpload?

    enum CodingKeys: String, CodingKey {
        case clusterIndex = "cluster_index"
        case memoryID = "memory_id"
        case mediaCount = "media_count"
        case upload
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clusterIndex = try c.decode(Int.self, forKey: .clusterIndex)
        memoryID = try c.decode(String.self, forKey: .memoryID)
        mediaCount = try c.decodeIfPresent(Int.self, forKey: .mediaCount) ?? 1
        upload = try c.decodeIfPresent(ImportedMemoryUpload.self, forKey: .upload)
    }
}

public struct ImportMemoriesResponse: Decodable, Sendable, Equatable {
    public let importID: String
    public let memories: [ImportedMemoryItem]

    enum CodingKeys: String, CodingKey {
        case importID = "import_id"
        case memories
    }
}
