import AuthenticationServices
import CryptoKit
import Foundation

#if os(iOS)
import UIKit

/// Google OAuth via ASWebAuthenticationSession + PKCE — no GoogleSignIn SDK.
/// Returns an `id_token` for `POST /v1/auth/social` (contract §2).
enum GoogleSignInService {
    enum SignInError: LocalizedError {
        case missingClientID
        case invalidClientID
        case cancelled
        case invalidCallback
        case tokenExchangeFailed
        case googleOAuthError(String)

        var errorDescription: String? {
            switch self {
            case .missingClientID: return "Google Sign-In is not configured yet."
            case .invalidClientID: return "Google client ID must end with .apps.googleusercontent.com."
            case .cancelled: return nil
            case .invalidCallback: return "Google sign-in did not complete. Try again."
            case .tokenExchangeFailed: return "Could not verify Google sign-in. Try again."
            case let .googleOAuthError(message): return message
            }
        }
    }

    /// iOS OAuth client redirect — Google assigns this automatically (no manual redirect URI field).
    /// Scheme: `com.googleusercontent.apps.{client-id-prefix}` → `{scheme}:/oauth2redirect`
    static func callbackScheme(for clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let prefix = String(clientID.dropLast(suffix.count))
        guard !prefix.isEmpty else { return nil }
        return "com.googleusercontent.apps.\(prefix)"
    }

    static func redirectURI(for clientID: String) -> String? {
        guard let scheme = callbackScheme(for: clientID) else { return nil }
        return "\(scheme):/oauth2redirect"
    }

    static func fetchIDToken(clientID: String) async throws -> String {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SignInError.missingClientID }
        guard let redirectURI = redirectURI(for: trimmed),
              let callbackScheme = callbackScheme(for: trimmed)
        else {
            throw SignInError.invalidClientID
        }

        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(from: verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmed),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = components.url else { throw SignInError.invalidCallback }

        let callbackURL = try await WebAuthSession.run(url: authURL, callbackScheme: callbackScheme)
        let callbackItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let oauthError = callbackItems.first(where: { $0.name == "error" })?.value {
            let detail = callbackItems.first(where: { $0.name == "error_description" })?.value ?? oauthError
            throw SignInError.googleOAuthError("Google rejected sign-in: \(detail)")
        }
        guard let code = callbackItems.first(where: { $0.name == "code" })?.value else {
            throw SignInError.invalidCallback
        }

        return try await exchangeCode(code, clientID: trimmed, redirectURI: redirectURI, verifier: verifier)
    }

    private static func exchangeCode(
        _ code: String,
        clientID: String,
        redirectURI: String,
        verifier: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code": code,
            "client_id": clientID,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SignInError.googleOAuthError(parseGoogleTokenError(from: data))
        }

        struct TokenResponse: Decodable {
            let idToken: String
            enum CodingKeys: String, CodingKey { case idToken = "id_token" }
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data).idToken, !token.isEmpty else {
            throw SignInError.tokenExchangeFailed
        }
        return token
    }

    private static func parseGoogleTokenError(from data: Data) -> String {
        struct GoogleError: Decodable {
            let error: String?
            let errorDescription: String?
            enum CodingKeys: String, CodingKey {
                case error
                case errorDescription = "error_description"
            }
        }
        if let parsed = try? JSONDecoder().decode(GoogleError.self, from: data) {
            if let detail = parsed.errorDescription, !detail.isEmpty {
                return "Google token error: \(detail)"
            }
            if let code = parsed.error, !code.isEmpty {
                return "Google token error: \(code)"
            }
        }
        return "Could not exchange Google sign-in code. Confirm the OAuth client is type iOS with bundle ID app.legacy.ios."
    }
}

private enum PKCE {
    static func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    static func challenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum WebAuthSession {
    @MainActor
    static func run(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let provider = PresentationContextProvider()
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GoogleSignInService.SignInError.cancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: GoogleSignInService.SignInError.invalidCallback)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = true
            if !session.start() {
                continuation.resume(throwing: GoogleSignInService.SignInError.invalidCallback)
            }
        }
    }
}

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
            ?? UIWindow()
    }
}

#endif
