import SwiftUI
import UIKit
import WanderFeature
import APIClient
import LocationEngine

@main
struct LegacyApp: App {
    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// Stable per-install identifier (resets only when all vendor apps are removed) — used
    /// for `X-Device-Id`. Phase 1 device binding; App Attest hardens this at M5.
    private static var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    private let apiClient = LegacyAPIClient(
        configuration: LegacyAPIConfiguration(
            baseURL: URL(string: "https://api.legacy.app")!,
            appVersion: appVersion,
            deviceID: deviceID
        )
    )
    private let locationEngine = LocationEngine()
    private let wanderCoordinator: WanderCoordinator

    init() {
        wanderCoordinator = WanderCoordinator(
            apiClient: apiClient,
            locationEngine: locationEngine
        )
    }

    var body: some Scene {
        WindowGroup {
            WanderFeatureRootView(coordinator: wanderCoordinator)
                .preferredColorScheme(.dark)
        }
    }
}
