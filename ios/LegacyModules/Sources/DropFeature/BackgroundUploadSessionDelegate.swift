#if os(iOS)
import Foundation
import os

/// Receives background URLSession lifecycle callbacks for fire-and-forget media uploads
/// (the extra photos of a multi-photo import). Owns the temp files those uploads stream from
/// and deletes each one when its task finishes.
public final class BackgroundUploadSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public static let shared = BackgroundUploadSessionDelegate()

    private static let log = Logger(subsystem: "app.legacy.ios", category: "bg-upload")

    /// Temp files are streamed from here and swept on launch in case a callback was missed.
    private static var tempDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("legacy-bg-uploads", isDirectory: true)
    }

    private let lock = NSLock()
    private var tempFiles: [Int: URL] = [:]
    private var backgroundCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Temp file lifecycle

    /// Write `data` to a unique temp file for a background upload task to stream from.
    public static func writeTempFile(_ data: Data) throws -> URL {
        let dir = tempDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(UUID().uuidString)
        try data.write(to: url, options: .atomic)
        return url
    }

    func register(taskIdentifier: Int, fileURL: URL) {
        lock.lock(); defer { lock.unlock() }
        tempFiles[taskIdentifier] = fileURL
    }

    /// Best-effort cleanup of orphaned temp files (e.g. uploads finished while the app was
    /// killed, so the in-memory map was empty). Safe to call on every launch / first use.
    public static func sweepStaleTempFiles() {
        let dir = tempDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-86_400) // 1 day
        for url in contents {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func cleanUp(taskIdentifier: Int) {
        lock.lock()
        let url = tempFiles.removeValue(forKey: taskIdentifier)
        lock.unlock()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - URLSession callbacks

    public func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundCompletionHandler = handler
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            Self.log.error("bg upload \(task.taskIdentifier) failed: \(error.localizedDescription, privacy: .public)")
        } else if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Non-2xx isn't an Error — the slot just stays pending (best-effort extra).
            Self.log.error("bg upload \(task.taskIdentifier) HTTP \(http.statusCode)")
        }
        cleanUp(taskIdentifier: task.taskIdentifier)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}
#endif
