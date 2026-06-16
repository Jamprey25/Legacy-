import Foundation

public enum MediaUploadError: Error, Sendable, Equatable {
    case invalidResponse(statusCode: Int)
    case transport(String)
}

/// PUT stripped media bytes to a signed S3 URL (contract §3 upload block).
public protocol MediaUploading: Sendable {
    func upload(data: Data, to url: URL, contentType: String) async throws
}

public struct URLSessionMediaUploader: MediaUploading {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func upload(data: Data, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, from: data)
        } catch {
            throw MediaUploadError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MediaUploadError.invalidResponse(statusCode: code)
        }
    }
}
