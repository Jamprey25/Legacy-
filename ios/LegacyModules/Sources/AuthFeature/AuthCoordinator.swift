import APIClient
import AuthenticationServices
import Foundation

#if os(iOS)

/// Sign-in flow coordinator. Persists session token to Keychain on success.
@MainActor
@Observable
public final class AuthCoordinator {
    public enum Route: Equatable {
        case welcome
        case dobGate(pending: PendingAuth)
        case emailEntry
        case emailOTP(email: String)
        case ageRestricted
    }

    public enum PendingAuth: Equatable {
        case email
        case social(provider: String, identityToken: String)
    }

    public private(set) var route: Route = .welcome
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    public var dob = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    public var email = ""
    public var otpCode = ""

    private let apiClient: LegacyAPIClient
    private let deviceID: String
    private let googleClientID: String?
    private let onAuthenticated: () -> Void
    private let onDevAdminSignIn: (() -> Void)?

    public var isGoogleSignInAvailable: Bool {
        guard let googleClientID else { return false }
        return !googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        apiClient: LegacyAPIClient,
        deviceID: String,
        googleClientID: String? = nil,
        onAuthenticated: @escaping () -> Void,
        onDevAdminSignIn: (() -> Void)? = nil
    ) {
        self.apiClient = apiClient
        self.deviceID = deviceID
        self.googleClientID = googleClientID
        self.onAuthenticated = onAuthenticated
        self.onDevAdminSignIn = onDevAdminSignIn
    }

    // MARK: - Social

    public func reportError(_ message: String) {
        errorMessage = message
    }

    public func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let token = AppleSignInSupport.identityToken(from: authorization) else {
                reportError("Apple sign-in did not return a token.")
                return
            }
            Task { await exchangeSocial(provider: "apple", identityToken: token, dob: nil) }
        case .failure(let error):
            if let message = AppleSignInSupport.userFacingError(for: error) {
                reportError(message)
            }
        }
    }

    public func beginGoogleSignIn() async {
        guard let googleClientID else {
            reportError("Google Sign-In is not configured yet.")
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let idToken = try await GoogleSignInService.fetchIDToken(clientID: googleClientID)
            await exchangeSocial(provider: "google", identityToken: idToken, dob: nil)
        } catch GoogleSignInService.SignInError.cancelled {
            return
        } catch {
            reportError((error as? LocalizedError)?.errorDescription ?? userFacingMessage(for: error))
        }
    }

    public func beginEmailSignIn() {
        errorMessage = nil
        route = .emailEntry
    }

    #if DEBUG
    /// Skips OAuth/OTP — local dev admin with stub API responses (DEBUG builds only).
    public func signInAsAdmin() {
        errorMessage = nil
        onDevAdminSignIn?()
    }
    #endif

    // MARK: - DOB gate

    public func confirmDOB() async {
        guard case let .dobGate(pending) = route else { return }

        if AuthFormatting.isUnder13(dob) {
            route = .ageRestricted
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch pending {
        case .email:
            await verifyEmailCode()
        case let .social(provider, identityToken):
            await exchangeSocial(
                provider: provider,
                identityToken: identityToken,
                dob: AuthFormatting.dobString(from: dob)
            )
        }
    }

    // MARK: - Email OTP

    public func sendEmailCode() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }
        email = trimmed
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await apiClient.authEmailStart(trimmed)
            otpCode = ""
            route = .emailOTP(email: trimmed)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    public func resendEmailCode() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await apiClient.authEmailStart(trimmed)
            errorMessage = nil
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    public func verifyEmailCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let code = otpCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.count == 6 else {
            errorMessage = "Enter the 6-digit code from your email."
            return
        }

        // DOB is only required for first-time sign-up; returning users omit it.
        let dobString: String? =
            if case .dobGate(.email) = route {
                AuthFormatting.dobString(from: dob)
            } else {
                nil
            }

        do {
            let response = try await apiClient.authEmailVerify(
                EmailVerifyRequest(
                    email: email,
                    code: code,
                    dob: dobString,
                    device: AuthFormatting.deviceInfo(deviceID: deviceID)
                )
            )
            try await finishAuth(response)
        } catch LegacyAPIError.unauthorized {
            errorMessage = "That code is incorrect or has expired. Tap 'Resend code' to get a new one."
        } catch let LegacyAPIError.invalidRequest(code, _) where code == "dob_required" {
            route = .dobGate(pending: .email)
        } catch let LegacyAPIError.forbidden(code, _) where code == "age_restricted" {
            route = .ageRestricted
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    public func backToWelcome() {
        errorMessage = nil
        otpCode = ""
        route = .welcome
    }

    // MARK: - Private

    private func exchangeSocial(provider: String, identityToken: String, dob: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await apiClient.authSocial(
                SocialAuthRequest(
                    provider: provider,
                    identityToken: identityToken,
                    dob: dob,
                    device: AuthFormatting.deviceInfo(deviceID: deviceID)
                )
            )
            try await finishAuth(response)
        } catch let LegacyAPIError.invalidRequest(code, message) where code == "dob_required" {
            route = .dobGate(pending: .social(provider: provider, identityToken: identityToken))
        } catch let LegacyAPIError.forbidden(code, _) where code == "age_restricted" {
            route = .ageRestricted
        } catch LegacyAPIError.unauthorized where provider == "google" {
            errorMessage =
                "Legacy rejected the Google token. On Vercel, GOOGLE_CLIENT_ID must exactly match the iOS client ID in Info.plist (not a Web client ID)."
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func finishAuth(_ response: AuthResponse) async throws {
        try KeychainSessionStore.save(token: response.sessionToken)
        let savedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        AccountProfileStore.save(
            userID: response.user.id,
            email: savedEmail.contains("@") ? savedEmail : nil
        )
        onAuthenticated()
    }

    private func userFacingMessage(for error: Error) -> String {
        switch error {
        case let LegacyAPIError.transport(message):
            return message
        case LegacyAPIError.unauthorized:
            return "Session expired. Please sign in again."
        case let LegacyAPIError.invalidRequest(_, message):
            return message
        case let LegacyAPIError.server(status):
            if status == 500 {
                return "Sign-in isn't fully configured on the server yet. Try email sign-in, or check back after env vars are set on Vercel."
            }
            return "Server error (\(status)). Try again later."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

#endif
