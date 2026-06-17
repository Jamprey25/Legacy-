import Foundation

#if os(iOS)
/// Background-capable upload session for resumable PUTs to signed URLs.
public final class BackgroundMediaUploader: MediaUploading, @unchecked Sendable {
    public static let sessionIdentifier = "app.legacy.ios.upload"

    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            self.session = URLSession(
                configuration: config,
                delegate: BackgroundUploadSessionDelegate.shared,
                delegateQueue: nil
            )
        }
    }

    public func upload(data: Data, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        try data.write(to: tempURL, options: .atomic)

        let response: URLResponse
        do {
            (_, response) = try await session.upload(for: request, fromFile: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw MediaUploadError.transport(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: tempURL)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MediaUploadError.invalidResponse(statusCode: code)
        }
    }
}
#endif
