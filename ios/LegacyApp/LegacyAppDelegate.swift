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
}
