import XCTest
@testable import SchedulingCore

final class NextFireDatesTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func test_picksNextFutureDate() {
        let r = Recurrence.dates(days: [CalendarDate(year: 2026, month: 7, day: 4),
                                        CalendarDate(year: 2026, month: 12, day: 25)],
                                 times: [TimeOfDay(hour: 8, minute: 30)])
        let now = date(2026, 6, 25, 12, 0)
        XCTAssertEqual(r.nextFireDate(after: now, calendar: cal), date(2026, 7, 4, 8, 30))
    }

    func test_allDatesPast_returnsNil() {
        let r = Recurrence.dates(days: [CalendarDate(year: 2020, month: 1, day: 1)],
                                 times: [TimeOfDay(hour: 8, minute: 30)])
        XCTAssertNil(r.nextFireDate(after: date(2026, 6, 25, 12, 0), calendar: cal))
    }
}
