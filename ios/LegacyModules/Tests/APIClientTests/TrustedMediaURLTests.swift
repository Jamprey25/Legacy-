import APIClient
import XCTest

final class TrustedMediaURLTests: XCTestCase {
    func testAcceptsVercelBlobHosts() {
        XCTAssertNotNil(TrustedMediaURL.mediaURL(from: "https://abc.public.blob.vercel-storage.com/memories/x.jpg"))
        XCTAssertNotNil(TrustedMediaURL.mediaURL(from: "https://abc.private.blob.vercel-storage.com/memories/x.jpg"))
        XCTAssertNotNil(TrustedMediaURL.mediaURL(from: "https://blob.vercel-storage.com/exports/x.json"))
    }

    func testRejectsUnknownHost() {
        XCTAssertNil(TrustedMediaURL.mediaURL(from: "https://evil.example.com/steal.jpg"))
        XCTAssertNil(TrustedMediaURL.mediaURL(from: "http://blob.vercel-storage.com/insecure.jpg"))
    }

    func testUploadURLAllowsS3() {
        XCTAssertNotNil(
            TrustedMediaURL.uploadURL(from: "https://bucket.s3.amazonaws.com/key?X-Amz-Signature=abc")
        )
    }
}
