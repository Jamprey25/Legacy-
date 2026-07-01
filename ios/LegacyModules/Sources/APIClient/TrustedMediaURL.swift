import Foundation

/// Client-side media URL allowlist (SEC-P3-3). Rejects unknown hosts before fetch/display.
public enum TrustedMediaURL {
    private static let storageHosts: Set<String> = [
        "blob.vercel-storage.com",
        "public.blob.vercel-storage.com",
        "private.blob.vercel-storage.com",
        "stub.storage.example",
        "stub.legacy.app",
    ]

    /// HTTPS GET for unlock thumbnails, export archives, and blob media.
    public static func mediaURL(from string: String?) -> URL? {
        validatedURL(from: string, allowedHosts: storageHosts)
    }

    /// Presigned PUT targets (S3/R2/stub) in addition to storage hosts.
    public static func uploadURL(from string: String?) -> URL? {
        guard let string, !string.isEmpty, let url = URL(string: string), url.scheme == "https" else {
            return nil
        }
        let host = url.host?.lowercased() ?? ""
        if host.contains("amazonaws.com")
            || host.contains("r2.cloudflarestorage.com")
            || host.contains("stub.storage.example")
        {
            return url
        }
        return mediaURL(from: string)
    }

    private static func validatedURL(from string: String?, allowedHosts: Set<String>) -> URL? {
        guard let string, !string.isEmpty, let url = URL(string: string), url.scheme == "https" else {
            return nil
        }
        let host = url.host?.lowercased() ?? ""
        let ok = allowedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        return ok ? url : nil
    }
}
