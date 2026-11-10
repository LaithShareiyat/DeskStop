import XCTest
@testable import SchedulingCore

final class NextFireWeeklyTests: XCTestCase {
    // Fixed UTC calendar makes the assertions deterministic.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func test_laterToday_whenWeekdayMatches() {
        // 2026-06-25 is a Thursday. now 08:00, fire 09:00 same day.
        let r = Recurrence.weekly(days: [.thursday], times: [TimeOfDay(hour: 9, minute: 0)])
        let now = date(2026, 6, 25, 8, 0)
        XCTAssertEqual(r.nextFireDate(after: now, calendar: cal), date(2026, 6, 25, 9, 0))
    }

    func test_rollsToNextMatchingWeekday_whenTodayTimePassed() {
        // Thursday 10:00, fire is Thu 09:00 (passed) → next Thursday.
        let r = Recurrence.weekly(days: [.thursday], times: [TimeOfDay(hour: 9, minute: 0)])
        let now = date(2026, 6, 25, 10, 0)
        XCTAssertEqual(r.nextFireDate(after: now, calendar: cal), date(2026, 7, 2, 9, 0))
    }

    func test_picksEarliestAcrossMultipleTimes() {
        let r = Recurrence.weekly(days: [.thursday],
                                  times: [TimeOfDay(hour: 17, minute: 0), TimeOfDay(hour: 9, minute: 0)])
        let now = date(2026, 6, 25, 10, 0) // 09:00 passed, 17:00 today is next
        XCTAssertEqual(r.nextFireDate(after: now, calendar: cal), date(2026, 6, 25, 17, 0))
    }

    func test_emptyDaysReturnsNil() {
        let r = Recurrence.weekly(days: [], times: [TimeOfDay(hour: 9, minute: 0)])
        XCTAssertNil(r.nextFireDate(after: date(2026, 6, 25, 8, 0), calendar: cal))
    }

    func test_unknownReturnsNil() {
        XCTAssertNil(Recurrence.unknown.nextFireDate(after: date(2026, 6, 25, 8, 0), calendar: cal))
    }
}
