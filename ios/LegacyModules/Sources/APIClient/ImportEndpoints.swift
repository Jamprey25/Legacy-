import Foundation

public struct ImportClusterInput: Encodable, Sendable {
    public let lat: Double
    public let lng: Double
    public let capturedAt: String
    public let assetCount: Int

    enum CodingKeys: String, CodingKey {
        case lat, lng
        case capturedAt = "captured_at"
        case assetCount = "asset_count"
    }

    public init(lat: Double, lng: Double, capturedAt: String, assetCount: Int) {
        self.lat = lat
        self.lng = lng
        self.capturedAt = capturedAt
        self.assetCount = assetCount
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
    public let upload: ImportedMemoryUpload?

    enum CodingKeys: String, CodingKey {
        case clusterIndex = "cluster_index"
        case memoryID = "memory_id"
        case upload
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
