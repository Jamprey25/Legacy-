import Foundation

@MainActor
public enum APNsTokenStore {
    public private(set) static var tokenHex: String?

    public static func update(from deviceToken: Data) {
        tokenHex = deviceToken.map { String(format: "%02x", $0) }.joined()
    }

    #if DEBUG
    public static func resetForTesting() {
        tokenHex = nil
    }
    #endif
}
