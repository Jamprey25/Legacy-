import APIClient
import DesignSystem
import SwiftUI

#if os(iOS)

public struct ProfileView: View {
    public init(apiClient: LegacyAPIClient, onSignOut: @escaping () -> Void) {
        self.apiClient = apiClient
        self.onSignOut = onSignOut
    }

    private let apiClient: LegacyAPIClient
    private let onSignOut: () -> Void

    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showDeleteAlert = false
    @State private var exportShareURL: URL?

    public var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Text(AccountProfileStore.displayLabel)
                        .foregroundStyle(LegacyColor.textSecondary)
                    #if DEBUG
                    if AccountProfileStore.isDevAdmin {
                        Text("Developer admin · offline stub API")
                            .font(LegacyFont.caption)
                            .foregroundStyle(LegacyColor.textSecondary)
                    }
                    #endif
                }

                Section {
                    Button("Export My Data") {
                        Task { await exportData() }
                    }
                    .disabled(isBusy)

                    Button("Sign Out") {
                        Task { await signOut() }
                    }
                    .disabled(isBusy)

                    Button("Delete Account", role: .destructive) {
                        showDeleteAlert = true
                    }
                    .disabled(isBusy)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(LegacyFont.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Profile")
            .overlay {
                if isBusy {
                    ProgressView()
                        .tint(LegacyColor.accent)
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
        }
        .preferredColorScheme(.dark)
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

#endif
