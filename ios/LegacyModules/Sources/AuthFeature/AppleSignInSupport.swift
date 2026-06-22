import AuthenticationServices
import Foundation

#if os(iOS)

enum AppleSignInSupport {
    static func identityToken(from authorization: ASAuthorization) -> String? {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken
        else { return nil }
        return String(data: tokenData, encoding: .utf8)
    }

    static func userFacingError(for error: Error) -> String? {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            return nil
        }
        return "Apple sign-in failed. Please try again."
    }
}

#endif
