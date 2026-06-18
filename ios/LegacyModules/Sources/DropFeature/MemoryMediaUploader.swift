import APIClient
import Foundation

/// Uploads memory media after POST /memories — presigned PUT (S3/R2/stub) or Vercel Blob handshake.
public struct MemoryMediaUploader: Sendable {
    private let apiClient: LegacyAPIClient
    private let presignedUploader: MediaUploading
    private let skipNetworkUpload: Bool

    public init(
        apiClient: LegacyAPIClient,
        presignedUploader: MediaUploading = URLSessionMediaUploader(),
        skipNetworkUpload: Bool = false
    ) {
        self.apiClient = apiClient
        self.presignedUploader = presignedUploader
        self.skipNetworkUpload = skipNetworkUpload
    }

    /// DEBUG admin — POST /memories succeeds via stubs; skip real PUT/Blob handshake.
    public static func devBypass(apiClient: LegacyAPIClient) -> MemoryMediaUploader {
        MemoryMediaUploader(apiClient: apiClient, skipNetworkUpload: true)
    }

    /// Returns the blob public URL when the Vercel path was used (for DEBUG webhook stub).
    @discardableResult
    public func upload(
        memoryID: String,
        data: Data,
        contentType: String,
        signedPutURL: String?,
        uploadHeaders: [String: String] = [:]
    ) async throws -> String? {
        if skipNetworkUpload {
            return "https://stub.legacy.app/\(VercelBlobUpload.pathname(memoryID: memoryID, contentType: contentType))"
        }

        if let signedPutURL, let url = URL(string: signedPutURL) {
            if Self.isPlaceholderUploadURL(signedPutURL) {
                throw MediaUploadError.transport(
                    "Server storage isn't configured. Vercel needs STORAGE_BACKEND=vercel-blob and BLOB_READ_WRITE_TOKEN."
                )
            }
            let type = uploadHeaders["Content-Type"] ?? contentType
            try await presignedUploader.upload(data: data, to: url, contentType: type)
            return nil
        }

        // Vercel Blob path: POST bytes to the backend, which stores them server-side
        // with the official @vercel/blob put(). Avoids reverse-engineering Vercel's
        // internal client-upload protocol (which 400s).
        return try await apiClient.uploadMemoryMediaDirect(
            memoryID: memoryID,
            data: data,
            contentType: contentType
        )
    }

    private static func isPlaceholderUploadURL(_ url: String) -> Bool {
        url.contains("stub.storage.example") || url.contains("s3.stub") || url.contains("stub.legacy.app")
    }
}
