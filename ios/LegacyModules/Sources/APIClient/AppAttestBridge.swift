import Foundation

#if os(iOS)
public enum AppAttestBridge {
    public static func currentAssertion() async -> AppAttestAssertionPayload? {
        await AppAttestCoordinator.shared.currentAssertion()
    }

    public static func currentAssertionBase64() async -> String? {
        await currentAssertion()?.attestation
    }
}
#else
public enum AppAttestBridge {
    public static func currentAssertion() async -> AppAttestAssertionPayload? { nil }
    public static func currentAssertionBase64() async -> String? { nil }
}
#endif
