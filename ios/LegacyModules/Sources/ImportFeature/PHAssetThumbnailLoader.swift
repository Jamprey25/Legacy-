#if os(iOS)
import Photos
import UIKit

/// Loads small, cached thumbnails for cluster preview rows so the user can *see* what
/// they're importing. Metadata-only clustering stays untouched — this runs lazily, on
/// demand, only for rows that scroll into view.
public enum PHAssetThumbnailLoader {
    private static let cache = NSCache<NSString, UIImage>()

    /// Loads a thumbnail for `assetID` sized for a `side`×`side` point square at `scale`.
    /// Returns nil if the asset is missing or Photos can't produce an image.
    public static func thumbnail(assetID: String, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let pixelSide = Int((side * scale).rounded())
        let key = "\(assetID)@\(pixelSide)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let target = CGSize(width: CGFloat(pixelSide), height: CGFloat(pixelSide))

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isSynchronous = false

            // Photos can fire this handler twice for iCloud assets: a degraded preview
            // first, then the full image. Skip degraded deliveries, and guard `resumed`
            // because resuming a CheckedContinuation twice is a fatal crash.
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                guard !resumed else { return }
                resumed = true
                if let image { cache.setObject(image, forKey: key) }
                continuation.resume(returning: image)
            }
        }
    }
}
#endif
