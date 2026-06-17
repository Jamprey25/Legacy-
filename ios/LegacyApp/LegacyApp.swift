import SwiftUI
import UIKit
import AuthFeature
import WanderFeature
import DropFeature
import MemoryLaneFeature
import DesignSystem
import APIClient
import LocationEngine
import SwiftData
#if DEBUG
import LegacyAPIStubs
#endif

@MainActor
@Observable
final class AppModel {
    var isAuthenticated = false

    func refreshSession() {
        isAuthenticated = (try? KeychainSessionStore.read()) != nil
    }

    func signOut() {
        try? KeychainSessionStore.delete()
        isAuthenticated = false
    }
}

@main
struct LegacyApp: App {
    private let apiClient: LegacyAPIClient
    private let locationEngine = LocationEngine()
    @State private var appModel = AppModel()

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private static var deviceID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    init() {
        #if DEBUG
        apiClient = LegacyAPIClient.stubbed()
        #else
        apiClient = LegacyAPIClient(
            configuration: LegacyAPIConfiguration(
                baseURL: URL(string: "https://api.legacy.app")!,
                appVersion: Self.appVersion,
                deviceID: Self.deviceID
            )
        )
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                appModel: appModel,
                apiClient: apiClient,
                locationEngine: locationEngine,
                deviceID: Self.deviceID
            )
            .onAppear { appModel.refreshSession() }
        }
        .modelContainer(for: DropDraft.self)
    }
}

private struct RootView: View {
    @Bindable var appModel: AppModel
    let apiClient: LegacyAPIClient
    let locationEngine: LocationEngine
    let deviceID: String

    var body: some View {
        Group {
            if appModel.isAuthenticated {
                MainTabView(
                    apiClient: apiClient,
                    locationEngine: locationEngine
                )
            } else {
                AuthFeatureRootView(
                    coordinator: AuthCoordinator(
                        apiClient: apiClient,
                        deviceID: deviceID,
                        onAuthenticated: { appModel.refreshSession() }
                    )
                )
            }
        }
    }
}

private struct MainTabView: View {
    let apiClient: LegacyAPIClient
    let locationEngine: LocationEngine

    var body: some View {
        TabView {
            WanderFeatureRootView(
                coordinator: WanderCoordinator(
                    apiClient: apiClient,
                    locationEngine: locationEngine
                )
            )
            .tabItem {
                Label("Wander", systemImage: "map")
            }

            DropFeatureRootView(
                coordinator: DropCoordinator(
                    apiClient: apiClient,
                    locationEngine: locationEngine
                )
            )
            .tabItem {
                Label("Drop", systemImage: "mappin.and.ellipse")
            }

            MemoryLaneFeatureRootView(
                coordinator: MemoryLaneCoordinator(
                    apiClient: apiClient,
                    locationEngine: locationEngine
                )
            )
            .tabItem {
                Label("Lane", systemImage: "photo.on.rectangle.angled")
            }
        }
        .tint(LegacyColor.accent)
        .task {
            locationEngine.requestWhenInUseAuthorization()
        }
    }
}
