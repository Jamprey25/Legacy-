import Foundation

#if os(iOS)
public enum AppAttestBridge {
    public static func currentAssertionBase64() async -> String? {
        await AppAttestCoordinator.shared.currentAssertionBase64()
    }
}
#else
public enum AppAttestBridge {
    public static func currentAssertionBase64() async -> String? { nil }
}
#endif
