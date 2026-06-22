import Foundation

#if os(iOS)
/// Background URLSession holder for future resumable S3 presigned PUTs.
///
/// Vercel Blob / stub PUTs use the foreground `URLSessionMediaUploader` because background
/// sessions cannot use async/await upload APIs (TN227).
public final class BackgroundMediaUploader: MediaUploading, @unchecked Sendable {
    public static let sessionIdentifier = "app.legacy.ios.upload"

    private let foregroundUploader = URLSessionMediaUploader()
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
        try await foregroundUploader.upload(data: data, to: url, contentType: contentType)
    }
}
#endif
