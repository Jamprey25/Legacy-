import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum EXIFStripError: Error, Sendable, Equatable {
    case invalidImage
    case encodeFailed
}

/// Strips all metadata from image bytes before upload (privacy guarantee — SEC-MED).
/// Synchronous ImageIO rewrite; safe to call on a background queue before network I/O.
public enum EXIFStripper {
    /// Rewrites `data` as a new image with pixel content preserved and **no** metadata dictionaries.
    public static func stripMetadata(from data: Data) throws -> Data {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let type = CGImageSourceGetType(source),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw EXIFStripError.invalidImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else {
            throw EXIFStripError.encodeFailed
        }

        // nil properties → no EXIF, GPS, IPTC, or orientation metadata written.
        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw EXIFStripError.encodeFailed
        }

        return output as Data
    }

    /// Decodes `data` directly to a bounded size and re-encodes as a metadata-free JPEG, in a
    /// **single** ImageIO pass. Used on the import hot path where a tight loop over a whole visit
    /// would otherwise allocate a full-resolution bitmap per photo and get the app jetsam-killed.
    ///
    /// Why this is memory-safe: `CGImageSourceCreateThumbnailAtIndex` with a max-pixel-size
    /// downsamples *while decoding* — the full-resolution bitmap is never allocated (the standard
    /// low-memory decode from "Image and Graphics Best Practices"). The whole rewrite runs inside
    /// an `autoreleasepool` so each photo's transient buffers are reclaimed immediately rather than
    /// accumulating across the caller's `await`s.
    ///
    /// Privacy: the output is built from raw pixels with only a compression-quality property — no
    /// EXIF/GPS/TIFF dictionaries are carried over, so this strips metadata by construction (same
    /// SEC-MED guarantee as `stripMetadata`). Orientation is baked into the pixels, so the image
    /// stays upright without an orientation tag.
    ///
    /// - Parameters:
    ///   - maxPixelSize: cap on the longest edge in pixels. Images smaller than this are not upscaled.
    ///   - quality: JPEG compression quality (0...1).
    public static func downsampledStrippedJPEG(
        from data: Data,
        maxPixelSize: Int,
        quality: CGFloat = 0.9
    ) throws -> Data {
        try autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw EXIFStripError.invalidImage
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                // Bake EXIF orientation into the pixels so we can drop the metadata safely.
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]

            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw EXIFStripError.invalidImage
            }

            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil
            ) else {
                throw EXIFStripError.encodeFailed
            }

            // Only a compression-quality property — no metadata dictionaries are written.
            let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)

            guard CGImageDestinationFinalize(destination) else {
                throw EXIFStripError.encodeFailed
            }

            return output as Data
        }
    }

    /// True when GPS or other location-bearing metadata is present (privacy-critical check).
    public static func hasLocationMetadata(in data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return false
        }
        if properties[kCGImagePropertyGPSDictionary as String] != nil {
            return true
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            let locationKeys: Set<String> = [
                kCGImagePropertyExifUserComment as String,
                "GPSLatitude",
                "GPSLongitude",
            ]
            if exif.keys.contains(where: { locationKeys.contains($0) }) {
                return true
            }
        }
        return false
    }

    /// True when ImageIO reports sensitive metadata dictionaries (used in tests).
    public static func hasMetadata(in data: Data) -> Bool {
        if hasLocationMetadata(in: data) { return true }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return false
        }
        // {PixelWidth, PixelHeight} may remain; GPS/EXIF/TIFF live in nested dicts.
        let metadataKeys: Set<String> = [
            kCGImagePropertyExifDictionary as String,
            kCGImagePropertyGPSDictionary as String,
            kCGImagePropertyTIFFDictionary as String,
            kCGImagePropertyIPTCDictionary as String,
            kCGImagePropertyMakerAppleDictionary as String,
        ]
        return properties.keys.contains(where: metadataKeys.contains)
    }
}