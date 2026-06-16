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

    /// True when ImageIO reports any metadata dictionary on the image (used in tests).
    public static func hasMetadata(in data: Data) -> Bool {
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