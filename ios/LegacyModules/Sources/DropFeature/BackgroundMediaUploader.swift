import Foundation

#if os(iOS)
/// Background `URLSession` for non-blocking media uploads. Used for the EXTRA photos of a
/// multi-photo import: the hero uploads in the foreground (guaranteed primary image + pin),
/// while the rest are handed to the OS here — they keep uploading after the import screen is
/// gone and survive app suspension, instead of 200 blocking foreground POSTs.
///
/// Background sessions require file-based upload tasks (no async/await, no in-memory body —
/// TN227), so each photo's bytes are written to a temp file the delegate deletes on finish.
public final class BackgroundMediaUploader: MediaUploading, @unchecked Sendable {
    public static let sessionIdentifier = "app.legacy.ios.upload"

    /// One background session per identifier per process — must be a singleton.
    public static let shared = BackgroundMediaUploader()

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
        BackgroundUploadSessionDelegate.sweepStaleTempFiles()
    }

    /// Enqueue a fire-and-forget background upload of `data` for an already-built request
    /// (headers + URL set by the caller; the body comes from a temp file). Returns
    /// immediately — completion and temp-file cleanup happen in the delegate.
    public func enqueue(request: URLRequest, data: Data) throws {
        let fileURL = try BackgroundUploadSessionDelegate.writeTempFile(data)
        let task = session.uploadTask(with: request, fromFile: fileURL)
        BackgroundUploadSessionDelegate.shared.register(taskIdentifier: task.taskIdentifier, fileURL: fileURL)
        task.resume()
    }

    public func upload(data: Data, to url: URL, contentType: String) async throws {
        try await foregroundUploader.upload(data: data, to: url, contentType: contentType)
    }
}
#endif
