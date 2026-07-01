import Foundation

/// Shared URLSession with TLS pinning for Legacy API traffic (SEC-P5-1).
public enum LegacyPinnedURLSession {
    private final class PinningDelegate: NSObject, URLSessionDelegate {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            LegacyCertificatePinning.handle(challenge: challenge, completionHandler: completionHandler)
        }
    }

    private static let delegate = PinningDelegate()
    private static let lock = NSLock()
    private static var defaultSession: URLSession?

    /// Pinning-enabled session. Reuses one default-configuration instance for API traffic.
    public static func session(configuration: URLSessionConfiguration = .default) -> URLSession {
        if configuration.identifier != nil {
            return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        }
        lock.lock()
        defer { lock.unlock() }
        if let defaultSession { return defaultSession }
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defaultSession = session
        return session
    }
}
