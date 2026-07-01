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
        uploadHeaders: [String: String] = [:],
        position: Int = 0
    ) async throws -> String? {
        if skipNetworkUpload {
            return "https://stub.legacy.app/\(VercelBlobUpload.pathname(memoryID: memoryID, contentType: contentType))"
        }

        if let signedPutURL, let url = TrustedMediaURL.uploadURL(from: signedPutURL) {
            if Self.isPlaceholderUploadURL(signedPutURL) {
                throw MediaUploadError.transport(
                    "Server storage isn't configured. Vercel needs STORAGE_BACKEND=vercel-blob and BLOB_READ_WRITE_TOKEN."
                )
            }
            let type = uploadHeaders["Content-Type"] ?? contentType
            try await presignedUploader.upload(data: data, to: url, contentType: type)
            await uploadThumbnailIfNeeded(memoryID: memoryID, data: data, contentType: contentType, position: position)
            return nil
        }

        // Vercel Blob path: POST bytes to the backend, which stores them server-side
        // with the official @vercel/blob put(). Avoids reverse-engineering Vercel's
        // internal client-upload protocol (which 400s).
        let url = try await apiClient.uploadMemoryMediaDirect(
            memoryID: memoryID,
            data: data,
            contentType: contentType,
            position: position
        )

        // Client-side grid thumbnail — best-effort, never blocks the main upload.
        await uploadThumbnailIfNeeded(memoryID: memoryID, data: data, contentType: contentType, position: position)

        return url
    }

    private func uploadThumbnailIfNeeded(
        memoryID: String,
        data: Data,
        contentType: String,
        position: Int
    ) async {
        guard contentType.hasPrefix("image/"),
              let thumb = try? EXIFStripper.thumbnailJPEG(from: data) else { return }
        _ = try? await apiClient.uploadMemoryMediaDirect(
            memoryID: memoryID,
            data: thumb,
            contentType: "image/jpeg",
            position: position,
            mediaRole: "thumbnail"
        )
    }

    private static func isPlaceholderUploadURL(_ url: String) -> Bool {
        url.contains("stub.storage.example") || url.contains("s3.stub") || url.contains("stub.legacy.app")
    }
}
