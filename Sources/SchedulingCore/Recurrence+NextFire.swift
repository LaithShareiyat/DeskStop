import Foundation

extension Recurrence {
    /// The next instant this recurrence fires strictly after `now`, or nil if
    /// it never will (empty, `.unknown` or exhausted `.dates`).
    public func nextFireDate(after now: Date, calendar: Calendar) -> Date? {
        switch self {
        case let .weekly(days, times):
            return nextWeekly(days: days, times: times, after: now, calendar: calendar)
        case let .dates(days, times):
            return nextDates(days: days, times: times, after: now, calendar: calendar)
        case .unknown:
            return nil
        }
    }

    private func nextWeekly(days: Set<Weekday>, times: [TimeOfDay],
                            after now: Date, calendar: Calendar) -> Date? {
        guard !days.isEmpty, !times.isEmpty else { return nil }
        var best: Date?
        // 0...7 covers "later today" through "same weekday next week".
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let wd = calendar.component(.weekday, from: day)
            guard let weekday = Weekday(rawValue: wd), days.contains(weekday) else { continue }
            for t in times {
                guard let candidate = calendar.date(bySettingHour: t.hour, minute: t.minute,
                                                    second: 0, of: day) else { continue }
                if candidate > now, best == nil || candidate < best! { best = candidate }
            }
        }
        return best
    }

    private func nextDates(days: [CalendarDate], times: [TimeOfDay],
                           after now: Date, calendar: Calendar) -> Date? {
        guard !days.isEmpty, !times.isEmpty else { return nil }
        var best: Date?
        for d in days {
            for t in times {
                let comps = DateComponents(year: d.year, month: d.month, day: d.day,
                                           hour: t.hour, minute: t.minute, second: 0)
                guard let candidate = calendar.date(from: comps) else { continue }
                if candidate > now, best == nil || candidate < best! { best = candidate }
            }
        }
        return best
    }
}
