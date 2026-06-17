#if os(iOS)
import Foundation

/// Receives background URLSession completion callbacks for resumable uploads.
public final class BackgroundUploadSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    public static let shared = BackgroundUploadSessionDelegate()

    private var backgroundCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
    }

    public func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundCompletionHandler = handler
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}
#endif
