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
import LegacyAPIStubs

@MainActor
@Observable
final class AppModel {
    var isAuthenticated = false
    private(set) var apiClient: LegacyAPIClient

    init(appVersion: String, deviceID: String) {
        apiClient = Self.makeAPIClient(appVersion: appVersion, deviceID: deviceID)
    }

    static func makeAPIClient(appVersion: String, deviceID: String) -> LegacyAPIClient {
        #if DEBUG
        if AccountProfileStore.isDevAdmin || Self.usesStubAPI {
            let transport: StubHTTPTransport = AccountProfileStore.isDevAdmin ? .happyPath() : .qaAuthFlow()
            return LegacyAPIClient.stubbed(
                transport: transport,
                token: (try? KeychainSessionStore.read()) ?? "stub-token"
            )
        }
        #endif
        return LegacyAPIClient(
            configuration: LegacyAPIConfiguration(
                baseURL: URL(string: "https://legacy-backend-jamprey25s-projects.vercel.app")!,
                appVersion: appVersion,
                deviceID: deviceID
            )
        )
    }

    func refreshSession() {
        isAuthenticated = (try? KeychainSessionStore.read()) != nil
    }

    func signOut() {
        try? KeychainSessionStore.delete()
        AccountProfileStore.clear()
        #if os(iOS)
        AppAttestKeyStore.clear()
        #endif
        #if DEBUG
        apiClient = Self.makeAPIClient(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0",
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )
        #endif
        isAuthenticated = false
    }

    #if DEBUG
    /// Xcode: Edit Scheme → Run → Arguments → add `-LegacyUseStubAPI` for offline QA (email OTP, drop, wander).
    private static var usesStubAPI: Bool {
        ProcessInfo.processInfo.arguments.contains("-LegacyUseStubAPI")
    }

    func signInAsDevAdmin() {
        try? KeychainSessionStore.save(token: "stub-token")
        AccountProfileStore.saveDevAdmin()
        apiClient = LegacyAPIClient.stubbed(token: "stub-token")
        isAuthenticated = true
    }

    func makeMediaUploader() -> MemoryMediaUploader {
        if AccountProfileStore.isDevAdmin {
            return .devBypass(apiClient: apiClient)
        }
        return MemoryMediaUploader(apiClient: apiClient)
    }
    #else
    func makeMediaUploader() -> MemoryMediaUploader {
        MemoryMediaUploader(apiClient: apiClient)
    }
    #endif
}

@main
struct LegacyApp: App {
    @UIApplicationDelegateAdaptor(LegacyAppDelegate.self) private var appDelegate

    private let locationEngine = LocationEngine()
    @State private var appModel: AppModel

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
            #if os(iOS)
            AppAttestKeyStore.clear()
            #endif
        }
        KeychainSessionStore.clearIfFreshInstall()
        _appModel = State(initialValue: AppModel(appVersion: Self.appVersion, deviceID: Self.deviceID))
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                appModel: appModel,
                locationEngine: locationEngine,
                deviceID: Self.deviceID,
                googleClientID: Self.googleClientID
            )
            .onAppear {
                appModel.refreshSession()
                #if os(iOS)
                AppAttestCoordinator.shared.configure(apiClient: appModel.apiClient)
                if appModel.isAuthenticated {
                    Task { await AppAttestCoordinator.shared.ensureRegistered() }
                }
                #endif
            }
        }
        .modelContainer(for: DropDraft.self)
    }
}

private struct RootView: View {
    @Bindable var appModel: AppModel
    let locationEngine: LocationEngine
    let deviceID: String
    let googleClientID: String?

    @ViewBuilder
    var body: some View {
        if appModel.isAuthenticated {
            MainTabView(
                appModel: appModel,
                locationEngine: locationEngine
            )
        } else {
            #if DEBUG
            AuthFeatureRootView(
                coordinator: AuthCoordinator(
                    apiClient: appModel.apiClient,
                    deviceID: deviceID,
                    googleClientID: googleClientID,
                    onAuthenticated: {
                        appModel.refreshSession()
                        Task { await AppAttestCoordinator.shared.ensureRegistered() }
                    },
                    onDevAdminSignIn: { appModel.signInAsDevAdmin() }
                )
            )
            #else
            AuthFeatureRootView(
                coordinator: AuthCoordinator(
                    apiClient: appModel.apiClient,
                    deviceID: deviceID,
                    googleClientID: googleClientID,
                    onAuthenticated: {
                        appModel.refreshSession()
                        Task { await AppAttestCoordinator.shared.ensureRegistered() }
                    }
                )
            )
            #endif
        }
    }
}

private enum MainTab: Hashable {
    case wander, drop, importTab, lane, profile
}

private struct MainTabView: View {
    @Bindable var appModel: AppModel
    let locationEngine: LocationEngine

    @Environment(\.modelContext) private var modelContext
    @State private var backgroundLocation = BackgroundLocationCoordinator()
    @State private var wanderCoordinator: WanderCoordinator
    @State private var dropCoordinator: DropCoordinator
    @State private var importCoordinator: ImportCoordinator
    @State private var memoryLaneCoordinator: MemoryLaneCoordinator
    @State private var pinCelebration = PinDropCelebrationCoordinator()
    @State private var showBackgroundDiscoveryPrompt = false
    @State private var selectedTab: MainTab = .wander

    init(appModel: AppModel, locationEngine: LocationEngine) {
        self.appModel = appModel
        self.locationEngine = locationEngine
        _wanderCoordinator = State(initialValue: WanderCoordinator(
            apiClient: appModel.apiClient,
            locationEngine: locationEngine,
            networkMonitor: NetworkMonitor.shared
        ))
        _dropCoordinator = State(initialValue: DropCoordinator(
            apiClient: appModel.apiClient,
            locationEngine: locationEngine,
            mediaUploader: appModel.makeMediaUploader()
        ))
        _importCoordinator = State(initialValue: ImportCoordinator(
            apiClient: appModel.apiClient,
            mediaUploader: appModel.makeMediaUploader()
        ))
        _memoryLaneCoordinator = State(initialValue: MemoryLaneCoordinator(
            apiClient: appModel.apiClient,
            locationEngine: locationEngine
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
                        await APNsRegistrationService.uploadTokenIfNeeded(apiClient: appModel.apiClient)
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
            Task { await APNsRegistrationService.uploadTokenIfNeeded(apiClient: appModel.apiClient) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProximityPushNotifications.received)) { notification in
            let openWander = notification.userInfo?["openWander"] as? Bool ?? false
            handleProximityPush(openWander: openWander)
        }
        .onChange(of: dropCoordinator.state) { _, newState in
            if case .succeeded = newState, let pin = dropCoordinator.consumeCelebrationPin() {
                celebratePins([pin])
            }
        }
        .onChange(of: importCoordinator.phase) { _, phase in
            if case .completed = phase {
                let pins = importCoordinator.consumeCelebrationPins()
                if !pins.isEmpty { celebratePins(pins) }
            }
        }
        .task {
            NetworkMonitor.shared.start()
            await DropDraftRecovery.retryPendingDrafts(
                context: modelContext,
                mediaUploader: appModel.makeMediaUploader()
            )
            backgroundLocation.onRegionEntered = { regionID in
                if let result = await BackgroundRegionScanService.scanOnRegionEntry(
                    regionIdentifier: regionID,
                    apiClient: appModel.apiClient,
                    locationEngine: locationEngine
                ) {
                    wanderCoordinator.ingestBackgroundScan(result)
                }
            }
            await backgroundLocation.startIfAuthorized()
            await APNsRegistrationService.uploadTokenIfNeeded(apiClient: appModel.apiClient)
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

    private func celebratePins(_ pins: [CachedOwnPin]) {
        selectedTab = .wander
        Task {
            await pinCelebration.celebrate(pins: pins, wander: wanderCoordinator)
            await wanderCoordinator.scanIfNeeded(force: true)
        }
    }

    private func handleProximityPush(openWander: Bool) {
        if openWander { selectedTab = .wander }
        Task { await wanderCoordinator.scanIfNeeded(force: true) }
    }

    @ViewBuilder
    private var wanderTab: some View {
        WanderFeatureRootView(
            coordinator: wanderCoordinator,
            pinCelebration: pinCelebration
        )
            .tabItem { Label("Wander", systemImage: "map") }
            .tag(MainTab.wander)
    }

    @ViewBuilder
    private var dropTab: some View {
        DropFeatureRootView(coordinator: dropCoordinator)
        .tabItem { Label("Drop", systemImage: "mappin.and.ellipse") }
        .tag(MainTab.drop)
    }

    @ViewBuilder
    private var importTab: some View {
        ImportFeatureRootView(coordinator: importCoordinator)
        .tabItem { Label("Import", systemImage: "square.stack.3d.up") }
        .tag(MainTab.importTab)
    }

    @ViewBuilder
    private var laneTab: some View {
        MemoryLaneFeatureRootView(coordinator: memoryLaneCoordinator)
        .tabItem { Label("Lane", systemImage: "photo.on.rectangle.angled") }
        .tag(MainTab.lane)
    }

    @ViewBuilder
    private var profileTab: some View {
        ProfileView(
            apiClient: appModel.apiClient,
            onSignOut: { appModel.signOut() }
        )
        .tabItem { Label("Profile", systemImage: "person.circle") }
        .tag(MainTab.profile)
    }
}
