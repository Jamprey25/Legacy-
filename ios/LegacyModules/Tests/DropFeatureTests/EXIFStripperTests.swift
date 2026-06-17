import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DropFeature

final class EXIFStripperTests: XCTestCase {

    func testStripRemovesGPSMetadata() throws {
        let original = try makeJPEGWithGPSMetadata()
        XCTAssertTrue(EXIFStripper.hasLocationMetadata(in: original))

        let stripped = try EXIFStripper.stripMetadata(from: original)
        XCTAssertFalse(EXIFStripper.hasLocationMetadata(in: stripped))
        XCTAssertGreaterThan(stripped.count, 0)
    }

    func testStripPreservesDecodableImage() throws {
        let original = try makeJPEGWithGPSMetadata()
        let stripped = try EXIFStripper.stripMetadata(from: original)

        guard let source = CGImageSourceCreateWithData(stripped as CFData, nil) else {
            XCTFail("Stripped bytes are not a valid image")
            return
        }
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func makeJPEGWithGPSMetadata() throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bytesPerRow: 8,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let image = context.makeImage()
        else {
            throw EXIFStripError.invalidImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw EXIFStripError.encodeFailed
        }

        let gps: [String: Any] = [
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 37.7749,
                kCGImagePropertyGPSLatitudeRef as String: "N",
            ],
        ]
        CGImageDestinationAddImage(destination, image, gps as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw EXIFStripError.encodeFailed
        }

        return output as Data
    }
}
