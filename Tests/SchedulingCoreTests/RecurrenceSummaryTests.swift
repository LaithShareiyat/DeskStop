import XCTest
@testable import SchedulingCore

final class RecurrenceSummaryTests: XCTestCase {
    func test_weekdaysSummary() {
        let r = Recurrence.weekly(days: [.monday, .tuesday, .wednesday, .thursday, .friday],
                                  times: [TimeOfDay(hour: 9, minute: 0)])
        XCTAssertEqual(r.summary(), "Weekdays at 9:00 AM")
    }

    func test_dailySummary() {
        let r = Recurrence.weekly(days: Set(Weekday.allCases),
                                  times: [TimeOfDay(hour: 13, minute: 30)])
        XCTAssertEqual(r.summary(), "Daily at 1:30 PM")
    }

    func test_datesSummary() {
        let r = Recurrence.dates(days: [CalendarDate(year: 2026, month: 7, day: 4),
                                        CalendarDate(year: 2026, month: 12, day: 25)],
                                 times: [TimeOfDay(hour: 8, minute: 0)])
        XCTAssertEqual(r.summary(), "2 dates at 8:00 AM")
    }

    func test_unknownSummary() {
        XCTAssertEqual(Recurrence.unknown.summary(), "Unsupported schedule")
    }
}
