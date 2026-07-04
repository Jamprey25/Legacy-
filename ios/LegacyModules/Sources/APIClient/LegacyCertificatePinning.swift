import CryptoKit
import Foundation
import Security

/// TLS certificate pinning for the Legacy API host (SEC-P5-1).
///
/// Pins SHA-256 hashes of leaf certificate DER. Update `productionCertificatePins`
/// when Vercel rotates the deployment certificate (typically ~90 days).
public enum LegacyCertificatePinning {
    /// Host → allowed base64 SHA-256 certificate DER hashes (any chain cert may match).
    static let productionCertificatePins: [String: Set<String>] = [
        "legacy-backend-jamprey25s-projects.vercel.app": [
            // Captured 2026-07-01 via:
            // openssl s_client … | openssl x509 -outform der | openssl dgst -sha256 -binary | base64
            "7lTLEfFswxGzrLrlf4+7A/M4wbKiDecnIsPq/Q2uAUA=",
        ],
    ]

    static func shouldPin(host: String) -> Bool {
        productionCertificatePins[host] != nil
    }

    public static func handle(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        guard shouldPin(host: host), let allowed = productionCertificatePins[host], !allowed.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if chainMatchesPins(trust: trust, allowed: allowed) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func chainMatchesPins(trust: SecTrust, allowed: Set<String>) -> Bool {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return false }
        for certificate in chain {
            if let hash = certificateSHA256Base64(certificate), allowed.contains(hash) {
                return true
            }
        }
        return false
    }

    static func certificateSHA256Base64(_ certificate: SecCertificate) -> String? {
        let data = SecCertificateCopyData(certificate) as Data
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
    }
}
