import Foundation

/// Routes proximity APNs alerts into the Wander tab + scan refresh loop.
@MainActor
enum ProximityPushNotifications {
    static let received = Notification.Name("legacy.proximityPush.received")

    private(set) static var pendingWanderRefresh = false
    private(set) static var pendingOpenWander = false

    static func post(openWander: Bool) {
        if openWander { pendingOpenWander = true }
        pendingWanderRefresh = true
        NotificationCenter.default.post(
            name: received,
            object: nil,
            userInfo: ["openWander": openWander]
        )
    }

    static func consumePending() -> (refresh: Bool, openWander: Bool) {
        let refresh = pendingWanderRefresh
        let openWander = pendingOpenWander
        pendingWanderRefresh = false
        pendingOpenWander = false
        return (refresh, openWander)
    }
}
