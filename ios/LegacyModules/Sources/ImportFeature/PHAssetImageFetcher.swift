#if os(iOS)
import Foundation
import Photos
import UIKit

public enum PHAssetImageError: Error, Sendable {
    case notFound
    case decodeFailed
}

/// Loads JPEG bytes for a single asset when the user confirms import. Not used during clustering.
public enum PHAssetImageFetcher {
    public static func loadJPEGData(assetID: String) async throws -> Data {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else {
            throw PHAssetImageError.notFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: PHAssetImageError.decodeFailed)
                    return
                }
                if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.92) {
                    continuation.resume(returning: jpeg)
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
}
#endif
