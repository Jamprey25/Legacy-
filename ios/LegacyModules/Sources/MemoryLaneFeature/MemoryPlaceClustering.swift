import Foundation
import APIClient

extension MemoryLaneFormatting {
    /// ±`windowDays` around today's month/day in prior years. Falls back when exact-day is empty.
    static func isOnThisDayWindow(
        dropDate: String,
        windowDays: Int = 3,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard windowDays >= 0 else { return isOnThisDay(dropDate: dropDate, now: now, calendar: calendar) }
        guard let date = parseDay(dropDate) else { return false }
        let dropYear = calendar.component(.year, from: date)
        let todayYear = calendar.component(.year, from: now)
        guard dropYear < todayYear else { return false }

        guard let dropMonthDay = calendar.date(from: calendar.dateComponents([.month, .day], from: date)),
              let todayMonthDay = calendar.date(from: calendar.dateComponents([.month, .day], from: now)) else {
            return false
        }
        let delta = abs(calendar.dateComponents([.day], from: dropMonthDay, to: todayMonthDay).day ?? 999)
        return delta <= windowDays
    }

    static func onThisDayLabel(dropDate: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        if isOnThisDay(dropDate: dropDate, now: now, calendar: calendar) {
            return yearsAgoToday(dropDate: dropDate, now: now, calendar: calendar)
        }
        guard let date = parseDay(dropDate) else { return "" }
        let years = max(1, calendar.component(.year, from: now) - calendar.component(.year, from: date))
        let yearText = years == 1 ? "1 year ago" : "\(years) years ago"
        return "\(yearText) · nearby date"
    }
}

/// Groups memories into ~110m place buckets for the Places atlas.
enum MemoryPlaceClustering {
    static func bucketKey(lat: Double, lng: Double) -> String {
        String(format: "%.3f,%.3f", lat, lng)
    }

    static func cluster(items: [MemoryLaneItem]) -> [MemoryPlaceCluster] {
        var groups: [String: [MemoryLaneItem]] = [:]
        for item in items {
            guard let lat = item.lat, let lng = item.lng else { continue }
            let key = bucketKey(lat: lat, lng: lng)
            groups[key, default: []].append(item)
        }
        return groups.map { key, members in
            let coords = key.split(separator: ",").compactMap { Double($0) }
            return MemoryPlaceCluster(
                id: key,
                lat: coords.first ?? 0,
                lng: coords.last ?? 0,
                items: members.sorted { $0.dropDate > $1.dropDate }
            )
        }
        .sorted { $0.items.count > $1.items.count }
    }
}

public struct MemoryPlaceCluster: Identifiable, Equatable, Hashable {
    public let id: String
    public let lat: Double
    public let lng: Double
    public let items: [MemoryLaneItem]
    public var placeName: String?

    public var title: String {
        placeName ?? String(format: "%.3f°, %.3f°", lat, lng)
    }

    public init(id: String, lat: Double, lng: Double, items: [MemoryLaneItem], placeName: String? = nil) {
        self.id = id
        self.lat = lat
        self.lng = lng
        self.items = items
        self.placeName = placeName
    }
}
