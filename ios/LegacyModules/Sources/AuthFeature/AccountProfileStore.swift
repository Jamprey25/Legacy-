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
