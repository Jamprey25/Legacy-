import Foundation

/// Pure helpers for interpreting CLVisit callbacks (engineering-plan §7).
public enum CLVisitEvent {
    public static func isArrival(departureDate: Date) -> Bool {
        departureDate == .distantFuture
    }
}

#if os(iOS)
import CoreLocation

extension CLVisitEvent {
    static func isArrival(_ visit: CLVisit) -> Bool {
        isArrival(departureDate: visit.departureDate)
    }
}
#endif
