import Foundation
import Security

/// Short-lived Keychain buffer for OAuth identity tokens during the DOB gate (SEC-P5-6).
/// Avoids holding provider tokens in `@Observable` route state / memory longer than necessary.
public enum PendingOAuthTokenStore {
    private static let service = "com.legacy.pending-oauth"
    private static let ttl: TimeInterval = 600 // 10 minutes

    private struct Stored: Codable {
        let token: String
        let savedAt: Date
    }

    public enum StoreError: Error, Sendable {
        case unexpectedStatus(OSStatus)
    }

    public static func save(provider: String, identityToken: String) throws {
        let payload = Stored(token: identityToken, savedAt: Date())
        let data = try JSONEncoder().encode(payload)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
    }

    public static func load(provider: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw StoreError.unexpectedStatus(status)
        }

        let stored = try JSONDecoder().decode(Stored.self, from: data)
        if Date().timeIntervalSince(stored.savedAt) > ttl {
            try? delete(provider: provider)
            return nil
        }
        return stored.token
    }

    public static func clear() {
        for provider in ["apple", "google"] {
            try? delete(provider: provider)
        }
    }

    private static func delete(provider: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }
}
