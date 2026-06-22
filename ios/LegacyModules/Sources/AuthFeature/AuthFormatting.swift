import APIClient
import Foundation

#if os(iOS)
import UIKit
#endif

enum AuthFormatting {
    /// True when the user would be under 13 per contract §2 age gate (UTC calendar day).
    static func isUnder13(_ date: Date, reference: Date = Date()) -> Bool {
        ageYears(on: date, reference: reference) < 13
    }

    private static func ageYears(on dob: Date, reference: Date) -> Int {
        Calendar(identifier: .gregorian).dateComponents([.year], from: dob, to: reference).year ?? 0
    }

    /// Contract §2: `dob` as `yyyy-MM-dd`.
    static func dobString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func deviceInfo(deviceID: String) -> DeviceInfo {
        #if os(iOS)
        return DeviceInfo(
            deviceID: deviceID,
            model: UIDevice.current.model,
            osVersion: UIDevice.current.systemVersion
        )
        #else
        return DeviceInfo(deviceID: deviceID)
        #endif
    }
}
