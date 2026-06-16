import SwiftUI
import WanderFeature
import APIClient
import LocationEngine

@main
struct LegacyApp: App {
    private let apiClient = LegacyAPIClient(
        configuration: LegacyAPIConfiguration(
            baseURL: URL(string: "https://api.legacy.app")!,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
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
