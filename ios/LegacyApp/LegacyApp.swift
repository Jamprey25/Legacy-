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

@MainActor
@Observable
final class AppModel {
    var isAuthenticated = false

    func refreshSession() {
        isAuthenticated = (try? KeychainSessionStore.read()) != nil
    }

    func signOut() {
        try? KeychainSessionStore.delete()
        AccountProfileStore.clear()
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

    /// Set `LegacyGoogleClientID` in Info.plist when Joseph adds Google OAuth credentials.
    private static var googleClientID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "LegacyGoogleClientID") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    init() {
        if UserDefaults.standard.object(forKey: "legacyHasLaunched") == nil {
            AccountProfileStore.clear()
        }
        KeychainSessionStore.clearIfFreshInstall()
        apiClient = LegacyAPIClient(
            configuration: LegacyAPIConfiguration(
                baseURL: URL(string: "https://legacy-backend-jamprey25s-projects.vercel.app")!,
                appVersion: Self.appVersion,
                deviceID: Self.deviceID
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                appModel: appModel,
                apiClient: apiClient,
                locationEngine: locationEngine,
                deviceID: Self.deviceID,
                googleClientID: Self.googleClientID
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
    let googleClientID: String?

    @ViewBuilder
    var body: some View {
        if appModel.isAuthenticated {
            MainTabView(
                appModel: appModel,
                apiClient: apiClient,
                locationEngine: locationEngine
            )
        } else {
            AuthFeatureRootView(
                coordinator: AuthCoordinator(
                    apiClient: apiClient,
                    deviceID: deviceID,
                    googleClientID: googleClientID,
                    onAuthenticated: { appModel.refreshSession() }
                )
            )
        }
    }
}

private enum MainTab: Hashable {
    case wander, drop, importTab, lane, profile
}

private struct MainTabView: View {
    @Bindable var appModel: AppModel
    let apiClient: LegacyAPIClient
    let locationEngine: LocationEngine

    @Environment(\.modelContext) private var modelContext
    @State private var backgroundLocation = BackgroundLocationCoordinator()
    @State private var wanderCoordinator: WanderCoordinator
    @State private var showBackgroundDiscoveryPrompt = false
    @State private var selectedTab: MainTab = .wander

    init(appModel: AppModel, apiClient: LegacyAPIClient, locationEngine: LocationEngine) {
        self.appModel = appModel
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
        TabView(selection: $selectedTab) {
            wanderTab
            dropTab
            importTab
            laneTab
            profileTab
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
        .onReceive(NotificationCenter.default.publisher(for: ProximityPushNotifications.received)) { notification in
            let openWander = notification.userInfo?["openWander"] as? Bool ?? false
            handleProximityPush(openWander: openWander)
        }
        .task {
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
            let pending = ProximityPushNotifications.consumePending()
            if pending.refresh {
                if pending.openWander { selectedTab = .wander }
                await wanderCoordinator.scanIfNeeded(force: true)
            }
            if shouldOfferBackgroundDiscovery {
                showBackgroundDiscoveryPrompt = true
            }
        }
    }

    private func handleProximityPush(openWander: Bool) {
        if openWander { selectedTab = .wander }
        Task { await wanderCoordinator.scanIfNeeded(force: true) }
    }

    @ViewBuilder
    private var wanderTab: some View {
        WanderFeatureRootView(coordinator: wanderCoordinator)
            .tabItem { Label("Wander", systemImage: "map") }
            .tag(MainTab.wander)
    }

    @ViewBuilder
    private var dropTab: some View {
        DropFeatureRootView(
            coordinator: DropCoordinator(
                apiClient: apiClient,
                locationEngine: locationEngine
            )
        )
        .tabItem { Label("Drop", systemImage: "mappin.and.ellipse") }
        .tag(MainTab.drop)
    }

    @ViewBuilder
    private var importTab: some View {
        ImportFeatureRootView(
            coordinator: ImportCoordinator(apiClient: apiClient)
        )
        .tabItem { Label("Import", systemImage: "square.stack.3d.up") }
        .tag(MainTab.importTab)
    }

    @ViewBuilder
    private var laneTab: some View {
        MemoryLaneFeatureRootView(
            coordinator: MemoryLaneCoordinator(
                apiClient: apiClient,
                locationEngine: locationEngine
            )
        )
        .tabItem { Label("Lane", systemImage: "photo.on.rectangle.angled") }
        .tag(MainTab.lane)
    }

    @ViewBuilder
    private var profileTab: some View {
        ProfileView(
            apiClient: apiClient,
            onSignOut: { appModel.signOut() }
        )
        .tabItem { Label("Profile", systemImage: "person.circle") }
        .tag(MainTab.profile)
    }
}
