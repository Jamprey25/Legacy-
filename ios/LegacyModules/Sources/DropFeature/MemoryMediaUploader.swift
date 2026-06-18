import APIClient
import Foundation

/// Uploads memory media after POST /memories — presigned PUT (S3/R2/stub) or Vercel Blob handshake.
public struct MemoryMediaUploader: Sendable {
    private let apiClient: LegacyAPIClient
    private let presignedUploader: MediaUploading

    public init(
        apiClient: LegacyAPIClient,
        presignedUploader: MediaUploading = URLSessionMediaUploader()
    ) {
        self.apiClient = apiClient
        self.presignedUploader = presignedUploader
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
        if let signedPutURL, let url = URL(string: signedPutURL) {
            let type = uploadHeaders["Content-Type"] ?? contentType
            try await presignedUploader.upload(data: data, to: url, contentType: type)
            return nil
        }

        let result = try await VercelBlobUpload.uploadMemoryMedia(
            apiClient: apiClient,
            memoryID: memoryID,
            data: data,
            contentType: contentType
        )
        return result.url
    }
}
