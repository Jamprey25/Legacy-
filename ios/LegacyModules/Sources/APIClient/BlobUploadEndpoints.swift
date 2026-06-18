import Foundation

// MARK: - Vercel Blob client-upload handshake (api-contract §3.2)

struct BlobGenerateClientTokenRequest: Encodable {
    let type = "blob.generate-client-token"
    let payload: Payload

    struct Payload: Encodable {
        let pathname: String
        let multipart: Bool
        let clientPayload: String
    }
}

public struct BlobGenerateClientTokenResponse: Decodable, Sendable, Equatable {
    public let type: String
    public let clientToken: String

    enum CodingKeys: String, CodingKey {
        case type
        case clientToken
    }
}

public struct BlobPutResult: Decodable, Sendable, Equatable {
    public let url: String
    public let pathname: String
    public let contentType: String
}

public enum BlobUploadError: Error, Sendable, Equatable {
    case invalidClientToken
    case tokenRequestFailed(statusCode: Int)
    case uploadFailed(statusCode: Int)
    case transport(String)
}

public enum VercelBlobUpload {
    private static let apiBase = URL(string: "https://vercel.com/api/blob/")!
    private static let apiVersion = "12"

    /// Builds the storage pathname for a memory asset.
    public static func pathname(memoryID: String, contentType: String) -> String {
        let ext = fileExtension(for: contentType)
        return "memories/\(memoryID)/original.\(ext)"
    }

    /// Step 2 — PUT bytes to Vercel Blob using the scoped client token.
    public static func put(
        data: Data,
        pathname: String,
        contentType: String,
        clientToken: String,
        session: URLSession = .shared
    ) async throws -> BlobPutResult {
        guard clientToken.hasPrefix("vercel_blob_client_") else {
            throw BlobUploadError.invalidClientToken
        }

        let storeID = parseStoreID(from: clientToken)
        var components = URLComponents(url: apiBase, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "pathname", value: pathname)]

        guard let url = components.url else {
            throw BlobUploadError.transport("Invalid blob API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        request.setValue("public", forHTTPHeaderField: "x-vercel-blob-access")
        request.setValue(contentType, forHTTPHeaderField: "x-content-type")
        request.setValue(storeID, forHTTPHeaderField: "x-vercel-blob-store-id")
        request.setValue(apiVersion, forHTTPHeaderField: "x-api-version")
        request.setValue(String(data.count), forHTTPHeaderField: "x-content-length")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-api-blob-request-id")
        request.setValue("0", forHTTPHeaderField: "x-api-blob-request-attempt")

        let response: URLResponse
        let responseData: Data
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw BlobUploadError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw BlobUploadError.uploadFailed(statusCode: -1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw BlobUploadError.uploadFailed(statusCode: http.statusCode)
        }

        do {
            return try LegacyAPIClient.jsonDecoder.decode(BlobPutResult.self, from: responseData)
        } catch {
            throw BlobUploadError.transport("Could not decode blob upload response.")
        }
    }

    /// Full handshake: token from Legacy API → PUT to Vercel Blob.
    public static func uploadMemoryMedia(
        apiClient: LegacyAPIClient,
        memoryID: String,
        data: Data,
        contentType: String,
        session: URLSession = .shared
    ) async throws -> BlobPutResult {
        let pathname = pathname(memoryID: memoryID, contentType: contentType)
        let clientToken = try await apiClient.generateBlobClientToken(memoryID: memoryID, pathname: pathname)
        return try await put(
            data: data,
            pathname: pathname,
            contentType: contentType,
            clientToken: clientToken,
            session: session
        )
    }

    /// Marker stored in draft recovery when upload uses Vercel Blob (no presigned URL).
    public static let draftRecoveryMarker = "vercel-blob"

    public static func isDraftRecoveryMarker(_ value: String) -> Bool {
        value == draftRecoveryMarker
    }

    static func parseStoreID(from clientToken: String) -> String {
        // vercel_blob_client_{storeId}_{payload}
        let parts = clientToken.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count >= 5 else { return "" }
        return String(parts[3])
    }

    static func fileExtension(for contentType: String) -> String {
        switch contentType.lowercased() {
        case "image/png": return "png"
        case "image/webp": return "webp"
        case "video/mp4": return "mp4"
        default: return "jpg"
        }
    }
}
