#if os(iOS)
import Foundation
import Photos

public enum PHAssetImageError: Error, Sendable {
    case notFound
    case decodeFailed
}

/// Loads the original encoded bytes for a single asset when the user confirms import. Not used
/// during clustering.
///
/// Returns the asset's **original encoded data** (HEIC/JPEG) without decoding it into a bitmap.
/// Decoding/downsizing is deferred to `EXIFStripper.downsampledStrippedJPEG`, which decodes once
/// at a bounded size — so the full-resolution bitmap is never allocated here. (The previous
/// `UIImage(data:).jpegData()` round-trip decoded the entire image into memory, which on a large
/// multi-photo visit accumulated across the import loop and got the app jetsam-killed.)
public enum PHAssetImageFetcher {
    public static func loadImageData(assetID: String) async throws -> Data {
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
                // Photos fires this callback twice for iCloud assets: first a degraded
                // preview, then the full-quality data. Resuming a CheckedContinuation
                // twice is a fatal crash, so skip all degraded/intermediate deliveries.
                if info?[PHImageResultIsDegradedKey] as? Bool == true { return }

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: PHAssetImageError.decodeFailed)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }
}
#endif
