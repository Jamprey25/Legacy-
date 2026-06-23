import Foundation

#if os(iOS)
import DeviceCheck

/// Apple App Attest — key registration + per-request assertions (contract M5).
///
/// Flow matches backend `appAttest.ts`:
/// 1. `GET /v1/auth/attest/challenge` → HMAC `challenge_token`
/// 2. `clientDataHash = SHA256(hex_decode(token_prefix_before_dot))`
/// 3. Register once via `POST /v1/auth/attest/register`
/// 4. Attach base64 assertion on drop/unlock when `APP_ATTEST_REQUIRED` flips true
@MainActor
public final class AppAttestCoordinator {
    public static let shared = AppAttestCoordinator()

    private let service = DCAppAttestService.shared
    private var apiClient: LegacyAPIClient?

    private init() {}

    public func configure(apiClient: LegacyAPIClient) {
        self.apiClient = apiClient
    }

    public var isSupported: Bool {
        service.isSupported
    }

    /// Registers this install with the backend when App Attest is available.
    public func ensureRegistered() async {
        guard isSupported, let apiClient, !AppAttestKeyStore.isRegistered else { return }

        do {
            let challenge = try await apiClient.fetchAttestChallenge()
            let keyId = try await existingOrNewKeyId()
            let clientDataHash = try AppAttestChallenge.clientDataHash(for: challenge.challengeToken)
            let attestation = try await attestKey(keyId: keyId, clientDataHash: clientDataHash)
            try await apiClient.registerAppAttest(
                keyID: keyId,
                attestationBase64: attestation.base64EncodedString(),
                challengeToken: challenge.challengeToken
            )
            AppAttestKeyStore.markRegistered(keyId: keyId)
        } catch {
            // Non-fatal until APP_ATTEST_REQUIRED=true on backend.
        }
    }

    /// Base64 CBOR assertion for sensitive requests; `nil` on simulator / unsupported hardware.
    public func currentAssertionBase64() async -> String? {
        guard isSupported, apiClient != nil else { return nil }
        // Opportunistically self-heal registration before protected requests.
        // This prevents first-request failures when auth succeeded but register
        // has not completed yet (e.g. fresh install, keychain reset).
        if !AppAttestKeyStore.isRegistered {
            await ensureRegistered()
        }
        guard let keyId = AppAttestKeyStore.keyId, AppAttestKeyStore.isRegistered
        else { return nil }

        do {
            guard let apiClient else { return nil }
            let challenge = try await apiClient.fetchAttestChallenge()
            let clientDataHash = try AppAttestChallenge.clientDataHash(for: challenge.challengeToken)
            let assertion = try await generateAssertion(keyId: keyId, clientDataHash: clientDataHash)
            return assertion.base64EncodedString()
        } catch {
            return nil
        }
    }

    private func existingOrNewKeyId() async throws -> String {
        if let stored = AppAttestKeyStore.keyId { return stored }
        return try await withCheckedThrowingContinuation { continuation in
            service.generateKey { keyId, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let keyId else {
                    continuation.resume(throwing: AppAttestError.keyGenerationFailed)
                    return
                }
                AppAttestKeyStore.save(keyId: keyId)
                continuation.resume(returning: keyId)
            }
        }
    }

    private func attestKey(keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            service.attestKey(keyId, clientDataHash: clientDataHash) { attestation, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let attestation else {
                    continuation.resume(throwing: AppAttestError.attestationFailed)
                    return
                }
                continuation.resume(returning: attestation)
            }
        }
    }

    private func generateAssertion(keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            service.generateAssertion(keyId, clientDataHash: clientDataHash) { assertion, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let assertion else {
                    continuation.resume(throwing: AppAttestError.assertionFailed)
                    return
                }
                continuation.resume(returning: assertion)
            }
        }
    }
}

enum AppAttestError: Error {
    case keyGenerationFailed
    case attestationFailed
    case assertionFailed
}

public enum AppAttestKeyStore {
    private static let keyIdKey = "legacyAppAttestKeyId"
    private static let registeredKey = "legacyAppAttestRegistered"

    public static var keyId: String? {
        UserDefaults.standard.string(forKey: keyIdKey)
    }

    public static var isRegistered: Bool {
        UserDefaults.standard.bool(forKey: registeredKey)
    }

    public static func save(keyId: String) {
        UserDefaults.standard.set(keyId, forKey: keyIdKey)
    }

    public static func markRegistered(keyId: String) {
        save(keyId: keyId)
        UserDefaults.standard.set(true, forKey: registeredKey)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: keyIdKey)
        UserDefaults.standard.removeObject(forKey: registeredKey)
    }
}

#endif
