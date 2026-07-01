import APIClient
import CryptoKit
import Foundation
import Security

/// Encrypted on-disk store for own-memory pin coordinates (SEC-P3-4).
enum OwnPinSecureStore {
    private static let legacyDefaultsKey = "legacy.own-memory-pins.v1"
    private static let keychainAccount = "legacy.own-pin-encryption-key"
    private static let fileName = "own-memory-pins.v2.enc"

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(fileName)
    }

    static func load() -> [CachedOwnPin] {
        migrateFromUserDefaultsIfNeeded()
        guard let encrypted = try? Data(contentsOf: storeURL), !encrypted.isEmpty else { return [] }
        guard let key = loadOrCreateKey(),
              let combined = try? AES.GCM.SealedBox(combined: encrypted),
              let plain = try? AES.GCM.open(combined, using: key),
              let pins = try? JSONDecoder().decode([CachedOwnPin].self, from: plain)
        else { return [] }
        return pins
    }

    static func save(_ pins: [CachedOwnPin]) {
        guard let key = loadOrCreateKey(),
              let plain = try? JSONEncoder().encode(pins),
              let sealed = try? AES.GCM.seal(plain, using: key),
              let combined = sealed.combined
        else { return }

        let url = storeURL
        try? ProtectedFileIO.write(combined, to: url)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: storeURL)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private static func migrateFromUserDefaultsIfNeeded() {
        guard !FileManager.default.fileExists(atPath: storeURL.path),
              let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
              let pins = try? JSONDecoder().decode([CachedOwnPin].self, from: data)
        else { return }
        save(pins)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    private static func loadOrCreateKey() -> SymmetricKey? {
        if let existing = readKeyFromKeychain() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        return writeKeyToKeychain(key) ? key : nil
    }

    private static func readKeyFromKeychain() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    @discardableResult
    private static func writeKeyToKeychain(_ key: SymmetricKey) -> Bool {
        let data = key.withUnsafeBytes { Data($0) }
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
        ] as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
