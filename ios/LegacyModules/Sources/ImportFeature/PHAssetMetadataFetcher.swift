#if os(iOS)
import CoreLocation
import Foundation
import Photos

public enum PHAssetMetadataError: Error, Sendable {
    case unauthorized
    case fetchFailed
}

/// Reads GPS + capture date from the photo library. **Never loads image bytes.**
public enum PHAssetMetadataFetcher {
    /// Max assets to scan per import pass (performance guard). Sorted newest-first, so this
    /// is the most-recent N photos. At 5k a heavy shooter only reached ~1 year back; 20k
    /// covers several years. Only GPS-tagged photos become memories (see the `asset.location`
    /// guard below), so the effective memory yield is a fraction of this.
    public static let maxAssetsToScan = 20_000

    public static func fetchGeoSamples() async throws -> [PhotoGeoSample] {
        let status = await requestAuthorization()
        guard status == .authorized || status == .limited else {
            throw PHAssetMetadataError.unauthorized
        }

        return await withCheckedContinuation { continuation in
            var samples: [PhotoGeoSample] = []

            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = maxAssetsToScan

            let assets = PHAsset.fetchAssets(with: .image, options: options)
            assets.enumerateObjects { asset, _, _ in
                guard let location = asset.location else { return }
                let coordinate = location.coordinate
                guard CLLocationCoordinate2DIsValid(coordinate) else { return }

                let capturedAt = asset.creationDate ?? Date()
                samples.append(
                    PhotoGeoSample(
                        id: asset.localIdentifier,
                        lat: coordinate.latitude,
                        lng: coordinate.longitude,
                        capturedAt: capturedAt
                    )
                )
            }

            continuation.resume(returning: samples)
        }
    }

    private static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
#endif
