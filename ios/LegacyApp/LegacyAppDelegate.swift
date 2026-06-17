import DropFeature
import UIKit

final class LegacyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundMediaUploader.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundUploadSessionDelegate.shared.setBackgroundCompletionHandler(completionHandler)
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            APNsTokenStore.update(from: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] registration failed:", error.localizedDescription)
    }
}
