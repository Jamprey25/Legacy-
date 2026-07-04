import APIClient
import DesignSystem
import DropFeature
import Foundation
import LocationEngine
import SwiftData
import WanderFeature

#if os(iOS)
/// Clears user-scoped local caches on sign-out / account delete (SEC-P1-2).
enum SessionDataPurge {
    @MainActor
    static func run(modelContext: ModelContext?) {
        OwnMemoryPinCache.clear()
        WanderScanCache.clear()
        CoarseZoneCache.clear()
        UserDefaults.standard.removeObject(forKey: "legacyPlaceNameCache")

        if let defaults = LegacyAppGroup.sharedDefaults {
            defaults.removeObject(forKey: "widget.onThisDay.title")
            defaults.removeObject(forKey: "widget.onThisDay.subtitle")
        }

        BackgroundUploadSessionDelegate.purgeAllTempFiles()
        PendingOAuthTokenStore.clear()

        if let modelContext {
            try? DropDraftStore.purgeAll(context: modelContext)
        }
    }
}
#endif
