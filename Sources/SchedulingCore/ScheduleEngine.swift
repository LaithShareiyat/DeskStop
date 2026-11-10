import Foundation

/// Pure selection logic over a set of schedules. No timers, no side effects.
public enum ScheduleEngine {
    /// The soonest fire instant across all enabled schedules, plus the ids of
    /// every enabled schedule that fires at exactly that instant.
    public static func nextFire(in schedules: [Schedule],
                                after now: Date,
                                calendar: Calendar) -> (date: Date, due: [UUID])? {
        var soonest: Date?
        var nextDates: [(id: UUID, date: Date)] = []
        for s in schedules where s.enabled {
            guard let d = s.recurrence.nextFireDate(after: now, calendar: calendar) else { continue }
            nextDates.append((s.id, d))
            if soonest == nil || d < soonest! { soonest = d }
        }
        guard let fire = soonest else { return nil }
        let due = nextDates.filter { $0.date == fire }.map { $0.id }
        return (fire, due)
    }
}
