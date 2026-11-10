import XCTest
@testable import SchedulingCore

final class ScheduleEngineTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
    private func weekly(_ h: Int, _ days: Set<Weekday>) -> Recurrence {
        .weekly(days: days, times: [TimeOfDay(hour: h, minute: 0)])
    }

    func test_picksSoonestEnabledSchedule() {
        let a = Schedule(name: "A", presetID: UUID(), recurrence: weekly(17, [.thursday]))
        let b = Schedule(name: "B", presetID: UUID(), recurrence: weekly(9, [.thursday]))
        let now = date(2026, 6, 25, 8, 0) // Thursday
        let result = ScheduleEngine.nextFire(in: [a, b], after: now, calendar: cal)
        XCTAssertEqual(result?.date, date(2026, 6, 25, 9, 0))
        XCTAssertEqual(result?.due, [b.id])
    }

    func test_disabledSchedulesIgnored() {
        var a = Schedule(name: "A", presetID: UUID(), recurrence: weekly(9, [.thursday]))
        a.enabled = false
        let now = date(2026, 6, 25, 8, 0)
        XCTAssertNil(ScheduleEngine.nextFire(in: [a], after: now, calendar: cal))
    }

    func test_simultaneousSchedules_allDue() {
        let a = Schedule(name: "A", presetID: UUID(), recurrence: weekly(9, [.thursday]))
        let b = Schedule(name: "B", presetID: UUID(), recurrence: weekly(9, [.thursday]))
        let now = date(2026, 6, 25, 8, 0)
        let result = ScheduleEngine.nextFire(in: [a, b], after: now, calendar: cal)
        XCTAssertEqual(Set(result?.due ?? []), [a.id, b.id])
    }

    func test_strictlyAfter_preventsRefiringSameInstant() {
        let a = Schedule(name: "A", presetID: UUID(), recurrence: weekly(9, [.thursday]))
        let fireInstant = date(2026, 6, 25, 9, 0)
        // Re-arming with `after` == the instant just fired must yield the NEXT week.
        let result = ScheduleEngine.nextFire(in: [a], after: fireInstant, calendar: cal)
        XCTAssertEqual(result?.date, date(2026, 7, 2, 9, 0))
    }
}
