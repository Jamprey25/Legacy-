import APIClient
import Foundation
import UIKit
import UserNotifications

@MainActor
enum APNsRegistrationService {
    /// Requests notification permission and registers with APNs. Returns false if the user declines alerts.
    static func requestAuthorizationAndRegister() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        UIApplication.shared.registerForRemoteNotifications()
        return true
    }

    static func uploadTokenIfNeeded(apiClient: LegacyAPIClient) async {
        guard let tokenHex = APNsTokenStore.tokenHex else { return }
        try? await apiClient.registerAPNsToken(APNsTokenRequest(apnsToken: tokenHex))
    }
}
