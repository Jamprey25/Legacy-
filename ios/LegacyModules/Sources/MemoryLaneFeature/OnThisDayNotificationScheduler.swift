#if os(iOS)
import APIClient
import Foundation
import UserNotifications

/// Schedules a local "on this day" reminder when memories match today's window.
public enum OnThisDayNotificationScheduler {
    private static let identifier = "legacy.on-this-day"

    public static func reschedule(with items: [MemoryLaneItem]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let matches = items.filter { MemoryLaneFormatting.isOnThisDayWindow(dropDate: $0.dropDate, windowDays: 3) }
        guard !matches.isEmpty else { return }

        let count = matches.count
        let body = count == 1
            ? "One memory from this week, years ago, is waiting in Memory Lane."
            : "\(count) memories from this week, years ago, are waiting in Memory Lane."

        let content = UNMutableNotificationContent()
        content.title = "On this day"
        content.body = body
        content.sound = .default

        var date = DateComponents()
        date.hour = 9
        date.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }
}
#endif
