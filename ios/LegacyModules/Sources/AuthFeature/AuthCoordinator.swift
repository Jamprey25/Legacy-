import APIClient
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
        case apple(identityToken: String)
        case email
    }

    public private(set) var route: Route = .welcome
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?

    public var dob = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    public var email = ""
    public var otpCode = ""

    private let apiClient: LegacyAPIClient
    private let deviceID: String
    private let onAuthenticated: () -> Void

    public init(
        apiClient: LegacyAPIClient,
        deviceID: String,
        onAuthenticated: @escaping () -> Void
    ) {
        self.apiClient = apiClient
        self.deviceID = deviceID
        self.onAuthenticated = onAuthenticated
    }

    // MARK: - Social

    public func appleSignInCompleted(identityToken: String) {
        route = .dobGate(pending: .apple(identityToken: identityToken))
    }

    public func googleSignInTapped() {
        errorMessage = "Google Sign In will be available once backend OAuth and a client ID are configured."
    }

    public func beginEmailSignIn() {
        errorMessage = nil
        route = .emailEntry
    }

    // MARK: - DOB gate

    public func confirmDOB() async {
        guard case let .dobGate(pending) = route else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let dobString = AuthFormatting.dobString(from: dob)

        do {
            switch pending {
            case let .apple(token):
                let response = try await apiClient.authSocial(
                    SocialAuthRequest(
                        provider: "apple",
                        identityToken: token,
                        dob: dobString,
                        device: AuthFormatting.deviceInfo(deviceID: deviceID)
                    )
                )
                try await finishAuth(response)
            case .email:
                route = .emailOTP(email: email)
            }
        } catch let LegacyAPIError.forbidden(code, message) where code == "age_restricted" {
            route = .ageRestricted
        } catch let LegacyAPIError.invalidRequest(code, message) where code == "dob_required" {
            errorMessage = message
        } catch {
            errorMessage = userFacingMessage(for: error)
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
            route = .dobGate(pending: .email)
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    public func verifyEmailCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let dobString = AuthFormatting.dobString(from: dob)

        do {
            let response = try await apiClient.authEmailVerify(
                EmailVerifyRequest(
                    email: email,
                    code: otpCode.trimmingCharacters(in: .whitespacesAndNewlines),
                    dob: dobString,
                    device: AuthFormatting.deviceInfo(deviceID: deviceID)
                )
            )
            try await finishAuth(response)
        } catch LegacyAPIError.unauthorized {
            errorMessage = "That code is invalid or expired. Request a new one."
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

    private func finishAuth(_ response: AuthResponse) async throws {
        try KeychainSessionStore.save(token: response.sessionToken)
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
            return "Server error (\(status)). Try again later."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

#endif
