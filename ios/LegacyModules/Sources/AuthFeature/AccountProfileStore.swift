import Foundation

#if os(iOS)

/// Lightweight profile metadata for the account screen. Not security-sensitive.
public enum AccountProfileStore {
    private static let emailKey = "legacyAccountEmail"
    private static let userIDKey = "legacyAccountUserID"
    private static let devAdminKey = "legacyDevAdmin"

    public static var isDevAdmin: Bool {
        UserDefaults.standard.bool(forKey: devAdminKey)
    }

    public static var displayLabel: String {
        if isDevAdmin { return "Admin" }
        if let email = UserDefaults.standard.string(forKey: emailKey), !email.isEmpty {
            return email
        }
        if let userID = UserDefaults.standard.string(forKey: userIDKey), !userID.isEmpty {
            return userID
        }
        return "Signed in"
    }

    /// Primary line for profile header (name, not raw email).
    public static var displayName: String {
        if isDevAdmin { return "Admin" }
        if let email = UserDefaults.standard.string(forKey: emailKey),
           email.contains("@") {
            let local = email.split(separator: "@").first.map(String.init) ?? email
            return local.capitalized
        }
        if let email = UserDefaults.standard.string(forKey: emailKey), !email.isEmpty {
            return email
        }
        return "Legacy member"
    }

    /// Secondary line under the display name (email, ID, or status).
    public static var profileSubtitle: String? {
        if isDevAdmin { return "Developer · offline stub API" }
        if let email = UserDefaults.standard.string(forKey: emailKey),
           email.contains("@") {
            return email
        }
        if let userID = UserDefaults.standard.string(forKey: userIDKey), !userID.isEmpty {
            return truncatedUserID(userID)
        }
        return nil
    }

    /// Monogram for the avatar placeholder.
    public static var avatarMonogram: String {
        if isDevAdmin { return "A" }
        let name = displayName
        let letters = name.split(separator: " ").compactMap { $0.first }.prefix(2)
        if letters.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return letters.map { String($0) }.joined().uppercased()
    }

    private static func truncatedUserID(_ userID: String) -> String {
        guard userID.count > 12 else { return userID }
        return "\(userID.prefix(8))…\(userID.suffix(4))"
    }

    public static func save(userID: String, email: String? = nil) {
        UserDefaults.standard.set(userID, forKey: userIDKey)
        if let email, !email.isEmpty {
            UserDefaults.standard.set(email, forKey: emailKey)
        }
    }

    /// DEBUG dev sign-in — stub API, fixed admin identity matching `LegacyFixtures.authSocial`.
    public static func saveDevAdmin() {
        UserDefaults.standard.set(true, forKey: devAdminKey)
        save(userID: "11111111-1111-1111-1111-111111111111", email: "Admin")
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: userIDKey)
        UserDefaults.standard.removeObject(forKey: devAdminKey)
    }
}

#endif
