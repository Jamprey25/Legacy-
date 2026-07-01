import Foundation
import Security

/// Keychain-backed session token storage. `WhenUnlockedThisDeviceOnly` (SEC-P5-2).
public enum KeychainSessionStore {
    private static let service = "com.legacy.session"
    private static let account = "session_token"

    public enum KeychainError: Error, Sendable {
        case unexpectedStatus(OSStatus)
        case dataConversionFailed
    }

    public static func save(token: String) throws {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public static func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        return token
    }

    public static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Keychain survives app delete on device; UserDefaults does not. Purge stale sessions on first launch after reinstall.
    public static func clearIfFreshInstall() {
        let flag = "legacyHasLaunched"
        guard UserDefaults.standard.object(forKey: flag) == nil else { return }
        try? delete()
        UserDefaults.standard.set(true, forKey: flag)
    }
}
