import SwiftUI
import UIKit
import CoreLocation
import AuthFeature
import WanderFeature
import DropFeature
import MemoryLaneFeature
import ImportFeature
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
    @UIApplicationDelegateAdaptor(LegacyAppDelegate.self) private var appDelegate

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

    @Environment(\.modelContext) private var modelContext
    @State private var backgroundLocation = BackgroundLocationCoordinator()
    @State private var wanderCoordinator: WanderCoordinator
    @State private var showBackgroundDiscoveryPrompt = false

    init(apiClient: LegacyAPIClient, locationEngine: LocationEngine) {
        self.apiClient = apiClient
        self.locationEngine = locationEngine
        _wanderCoordinator = State(initialValue: WanderCoordinator(
            apiClient: apiClient,
            locationEngine: locationEngine,
            networkMonitor: NetworkMonitor.shared
        ))
    }

    private var shouldOfferBackgroundDiscovery: Bool {
        guard !BackgroundLocationPermissionGate.hasUserDismissedPrompt else { return false }
        guard !backgroundLocation.isAuthorizedForBackground else { return false }
        guard locationEngine.authorizationStatus == .authorizedWhenInUse else { return false }
        return !wanderCoordinator.teasers.isEmpty || !wanderCoordinator.cachedOwnPins.isEmpty
    }

    var body: some View {
        TabView {
            WanderFeatureRootView(coordinator: wanderCoordinator)
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

            ImportFeatureRootView(
                coordinator: ImportCoordinator(apiClient: apiClient)
            )
            .tabItem {
                Label("Import", systemImage: "square.stack.3d.up")
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
        .sheet(isPresented: $showBackgroundDiscoveryPrompt) {
            BackgroundDiscoveryPermissionSheet(
                onEnable: {
                    backgroundLocation.requestAlwaysAuthorization()
                    Task {
                        _ = await APNsRegistrationService.requestAuthorizationAndRegister()
                        await APNsRegistrationService.uploadTokenIfNeeded(apiClient: apiClient)
                    }
                    showBackgroundDiscoveryPrompt = false
                },
                onDismiss: {
                    BackgroundLocationPermissionGate.markPromptDismissed()
                    showBackgroundDiscoveryPrompt = false
                }
            )
            .presentationDetents([.medium])
        }
        .onChange(of: wanderCoordinator.teasers.count) { _, _ in
            if shouldOfferBackgroundDiscovery {
                showBackgroundDiscoveryPrompt = true
            }
        }
        .onChange(of: APNsTokenStore.tokenHex) { _, _ in
            Task { await APNsRegistrationService.uploadTokenIfNeeded(apiClient: apiClient) }
        }
        .task {
            locationEngine.requestWhenInUseAuthorization()
            NetworkMonitor.shared.start()
            await DropDraftRecovery.retryPendingDrafts(context: modelContext, apiClient: apiClient)
            backgroundLocation.onRegionEntered = { regionID in
                if let result = await BackgroundRegionScanService.scanOnRegionEntry(
                    regionIdentifier: regionID,
                    apiClient: apiClient,
                    locationEngine: locationEngine
                ) {
                    wanderCoordinator.ingestBackgroundScan(result)
                }
            }
            await backgroundLocation.startIfAuthorized()
            await APNsRegistrationService.uploadTokenIfNeeded(apiClient: apiClient)
            if shouldOfferBackgroundDiscovery {
                showBackgroundDiscoveryPrompt = true
            }
        }
    }
}
