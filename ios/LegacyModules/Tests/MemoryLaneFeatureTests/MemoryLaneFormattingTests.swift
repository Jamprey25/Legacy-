import XCTest
@testable import MemoryLaneFeature

final class MemoryLaneFormattingTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testIsOnThisDayMatchesSameMonthDayInPastYear() {
        let now = date(2026, 6, 22)
        XCTAssertTrue(MemoryLaneFormatting.isOnThisDay(dropDate: "2023-06-22", now: now, calendar: calendar))
        XCTAssertTrue(MemoryLaneFormatting.isOnThisDay(dropDate: "2025-06-22", now: now, calendar: calendar))
    }

    func testIsOnThisDayRejectsToday() {
        let now = date(2026, 6, 22)
        // Same calendar day in the *current* year is "today", not a resurfaced memory.
        XCTAssertFalse(MemoryLaneFormatting.isOnThisDay(dropDate: "2026-06-22", now: now, calendar: calendar))
    }

    func testIsOnThisDayRejectsDifferentDay() {
        let now = date(2026, 6, 22)
        XCTAssertFalse(MemoryLaneFormatting.isOnThisDay(dropDate: "2023-06-21", now: now, calendar: calendar))
        XCTAssertFalse(MemoryLaneFormatting.isOnThisDay(dropDate: "2023-07-22", now: now, calendar: calendar))
    }

    func testIsOnThisDayRejectsFutureYear() {
        let now = date(2026, 6, 22)
        XCTAssertFalse(MemoryLaneFormatting.isOnThisDay(dropDate: "2027-06-22", now: now, calendar: calendar))
    }

    func testIsOnThisDayHandlesGarbage() {
        let now = date(2026, 6, 22)
        XCTAssertFalse(MemoryLaneFormatting.isOnThisDay(dropDate: "not-a-date", now: now, calendar: calendar))
    }

    func testYearOfParsesValidDates() {
        XCTAssertEqual(MemoryLaneFormatting.year(of: "2024-03-09", calendar: calendar), 2024)
        XCTAssertEqual(MemoryLaneFormatting.year(of: "1999-12-31", calendar: calendar), 1999)
    }

    func testYearOfReturnsNilForGarbage() {
        XCTAssertNil(MemoryLaneFormatting.year(of: "nope", calendar: calendar))
    }

    func testIsOnThisDayWindowAllowsNearbyDates() {
        let now = date(2026, 6, 22)
        XCTAssertTrue(MemoryLaneFormatting.isOnThisDayWindow(dropDate: "2023-06-24", windowDays: 3, now: now, calendar: calendar))
        XCTAssertFalse(MemoryLaneFormatting.isOnThisDayWindow(dropDate: "2023-06-16", windowDays: 3, now: now, calendar: calendar))
    }
}
