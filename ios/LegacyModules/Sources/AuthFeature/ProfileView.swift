import APIClient
import CoreLocation
import DesignSystem
import SwiftUI
import UserNotifications

#if os(iOS)

public struct ProfileView: View {
    public init(apiClient: LegacyAPIClient, onSignOut: @escaping () -> Void) {
        self.apiClient = apiClient
        self.onSignOut = onSignOut
    }

    private let apiClient: LegacyAPIClient
    private let onSignOut: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showDeleteAlert = false
    @State private var exportShareURL: URL?
    @State private var locationStatus = "Checking…"
    @State private var notificationStatus = "Checking…"
    @State private var showEditName = false
    @State private var displayName = AccountProfileStore.displayName

    public var body: some View {
        NavigationStack {
            ZStack {
                LegacyColor.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: LegacySpacing.xl) {
                        profileHero

                        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
                            ProfileSectionLabel("Data & privacy")
                            ProfileActionCard {
                                ProfileActionRow(
                                    title: "Export my data",
                                    subtitle: "Download a copy of your memories",
                                    icon: "square.and.arrow.up",
                                    action: { Task { await exportData() } }
                                )
                                .disabled(isBusy)
                            }
                        }

                        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
                            ProfileSectionLabel("App permissions")
                            ProfileActionCard {
                                ProfileActionRow(
                                    title: "Location",
                                    subtitle: locationStatus,
                                    icon: "location",
                                    action: openSystemSettings
                                )
                                ProfileActionRow(
                                    title: "Notifications",
                                    subtitle: notificationStatus,
                                    icon: "bell",
                                    action: openSystemSettings
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
                            ProfileSectionLabel("Account")
                            ProfileActionCard {
                                ProfileActionRow(
                                    title: "Display name",
                                    subtitle: displayName,
                                    icon: "person",
                                    action: { showEditName = true }
                                )
                                ProfileActionRow(
                                    title: "Sign out",
                                    subtitle: "End this session on this device",
                                    icon: "rectangle.portrait.and.arrow.right",
                                    action: { Task { await signOut() } }
                                )
                                .disabled(isBusy)
                            }
                        }

                        VStack(alignment: .leading, spacing: LegacySpacing.sm) {
                            ProfileSectionLabel("Danger zone")
                            ProfileActionCard {
                                ProfileActionRow(
                                    title: "Delete account",
                                    subtitle: "Permanently erase all memories",
                                    icon: "trash",
                                    tint: LegacyColor.danger,
                                    action: { showDeleteAlert = true }
                                )
                                .disabled(isBusy)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(LegacyFont.caption)
                                .foregroundStyle(LegacyColor.danger)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }

                        Text(appVersionLabel)
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.top, LegacySpacing.xs)
                    }
                    .padding(.horizontal, LegacySpacing.xl)
                    .padding(.top, LegacySpacing.md)
                    .padding(.bottom, LegacySpacing.xxl)
                }
            }
            .navigationTitle("Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .overlay {
                if isBusy {
                    ProgressView()
                        .tint(LegacyColor.accent)
                        .padding(LegacySpacing.lg)
                        .background(LegacyColor.surface.opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))
                }
            }
            .alert("Delete Account?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This permanently deletes all your memories and cannot be undone.")
            }
            .sheet(item: $exportShareURL) { url in
                ShareSheet(items: [url])
            }
            .sheet(isPresented: $showEditName) {
                EditNameSheet(currentName: displayName) { newName in
                    AccountProfileStore.customName = newName.isEmpty ? nil : newName
                    displayName = AccountProfileStore.displayName
                }
            }
            .task { await refreshPermissionStatuses() }
            .onChange(of: scenePhase) { _, phase in
                // Re-read after the user may have toggled permissions in Settings.
                if phase == .active { Task { await refreshPermissionStatuses() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshPermissionStatuses() async {
        locationStatus = Self.locationStatusText(CLLocationManager().authorizationStatus)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = Self.notificationStatusText(settings.authorizationStatus)
    }

    private static func locationStatusText(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "Always — full background discovery"
        case .authorizedWhenInUse: return "While using the app"
        case .denied: return "Off — tap to enable in Settings"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not set yet"
        @unknown default: return "Unknown"
        }
    }

    private static func notificationStatusText(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "On"
        case .provisional: return "Quiet delivery"
        case .ephemeral: return "Temporary"
        case .denied: return "Off — tap to enable in Settings"
        case .notDetermined: return "Not set yet"
        @unknown default: return "Unknown"
        }
    }

    private var profileHero: some View {
        VStack(spacing: LegacySpacing.md) {
            ZStack {
                Circle()
                    .fill(LegacyColor.accent.opacity(0.22))
                    .frame(width: 108, height: 108)
                    .blur(radius: 28)

                Circle()
                    .stroke(LegacyColor.accent.opacity(0.35), lineWidth: 1)
                    .frame(width: 88, height: 88)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                LegacyColor.surface,
                                LegacyColor.background,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .overlay {
                        Text(monogram(for: displayName))
                            .font(LegacyFont.title)
                            .foregroundStyle(LegacyColor.accent)
                    }
            }
            .padding(.top, LegacySpacing.sm)

            VStack(spacing: LegacySpacing.xs) {
                Text(displayName)
                    .font(LegacyFont.title2)
                    .foregroundStyle(LegacyColor.textPrimary)

                if let subtitle = AccountProfileStore.profileSubtitle {
                    Text(subtitle)
                        .font(LegacyFont.callout)
                        .foregroundStyle(LegacyColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            if AccountProfileStore.isDevAdmin {
                Text("Developer admin")
                    .font(LegacyFont.caption)
                    .foregroundStyle(LegacyColor.accent)
                    .padding(.horizontal, LegacySpacing.md)
                    .padding(.vertical, LegacySpacing.xs)
                    .background(LegacyColor.accent.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LegacySpacing.lg)
    }

    private func monogram(for name: String) -> String {
        let letters = name.split(separator: " ").compactMap { $0.first }.prefix(2)
        if letters.isEmpty { return String(name.prefix(1)).uppercased() }
        return letters.map { String($0) }.joined().uppercased()
    }

    private var appVersionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "Legacy \(version)"
    }

    private func exportData() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let response = try await apiClient.exportUserData()
            guard let url = URL(string: response.archiveURL) else {
                errorMessage = "Export succeeded but the download link was invalid."
                return
            }
            exportShareURL = url
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func signOut() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        try? await apiClient.logout()
        onSignOut()
    }

    private func deleteAccount() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            try await apiClient.deleteUser()
            onSignOut()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        switch error {
        case let LegacyAPIError.transport(message):
            return message
        case let LegacyAPIError.invalidRequest(_, message):
            return message
        case let LegacyAPIError.server(status):
            return "Server error (\(status)). Try again later."
        default:
            return "Something went wrong. Please try again."
        }
    }
}

// MARK: - Profile chrome

private struct ProfileSectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(LegacyFont.caption)
            .foregroundStyle(LegacyColor.textSecondary)
            .tracking(0.6)
    }
}

private struct ProfileActionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LegacyColor.surface,
                            LegacyColor.background.opacity(0.85),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: LegacyRadius.lg, style: .continuous)
                .stroke(LegacyColor.separator, lineWidth: 1)
        }
    }
}

private struct ProfileActionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = LegacyColor.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LegacySpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: LegacySpacing.xxs) {
                    Text(title)
                        .font(LegacyFont.headline)
                        .foregroundStyle(LegacyColor.textPrimary)
                    Text(subtitle)
                        .font(LegacyFont.caption)
                        .foregroundStyle(LegacyColor.textSecondary)
                }

                Spacer(minLength: LegacySpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LegacyColor.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, LegacySpacing.lg)
            .padding(.vertical, LegacySpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - Edit name sheet

private struct EditNameSheet: View {
    let currentName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String

    init(currentName: String, onSave: @escaping (String) -> Void) {
        self.currentName = currentName
        self.onSave = onSave
        _draft = State(initialValue: AccountProfileStore.customName ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LegacyColor.background.ignoresSafeArea()
                VStack(spacing: LegacySpacing.lg) {
                    TextField("Display name", text: $draft)
                        .font(LegacyFont.body)
                        .foregroundStyle(LegacyColor.textPrimary)
                        .padding(LegacySpacing.md)
                        .background(LegacyColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: LegacyRadius.md, style: .continuous))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)

                    Button("Clear name") {
                        draft = ""
                    }
                    .font(LegacyFont.callout)
                    .foregroundStyle(LegacyColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                }
                .padding(.horizontal, LegacySpacing.xl)
                .padding(.top, LegacySpacing.lg)
            }
            .navigationTitle("Display name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(LegacyColor.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .font(LegacyFont.headline)
                    .foregroundStyle(LegacyColor.accent)
                }
            }
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.height(220)])
    }
}

#endif
