import XCTest
@testable import APIClient

final class VercelBlobUploadTests: XCTestCase {

    func testPathnameUsesContentTypeExtension() {
        XCTAssertEqual(
            VercelBlobUpload.pathname(memoryID: "abc", contentType: "image/jpeg"),
            "memories/abc/original.jpg"
        )
        XCTAssertEqual(
            VercelBlobUpload.pathname(memoryID: "abc", contentType: "image/png"),
            "memories/abc/original.png"
        )
        XCTAssertEqual(
            VercelBlobUpload.pathname(memoryID: "abc", contentType: "video/mp4"),
            "memories/abc/original.mp4"
        )
    }

    func testParseStoreIDFromClientToken() {
        let token = "vercel_blob_client_store1234_encodedPayloadHere"
        XCTAssertEqual(VercelBlobUpload.parseStoreID(from: token), "store1234")
    }

    func testDraftRecoveryMarker() {
        XCTAssertTrue(VercelBlobUpload.isDraftRecoveryMarker(VercelBlobUpload.draftRecoveryMarker))
        XCTAssertFalse(VercelBlobUpload.isDraftRecoveryMarker("https://s3.example/put"))
    }

    func testGenerateClientTokenRequestEncodesClientPayload() throws {
        let payload = BlobGenerateClientTokenRequest.Payload(
            pathname: "memories/id/original.jpg",
            multipart: false,
            clientPayload: "{\"memory_id\":\"id\"}"
        )
        let body = BlobGenerateClientTokenRequest(payload: payload)
        let data = try LegacyAPIClient.jsonEncoder.encode(body)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("blob.generate-client-token"))
        XCTAssertTrue(json.contains("memory_id"))
    }
}
