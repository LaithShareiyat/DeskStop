import Foundation

extension TimeOfDay {
    /// 12-hour "9:00 AM" / "1:30 PM", locale-independent for stable summaries.
    public var displayString: String {
        let period = hour < 12 ? "AM" : "PM"
        var h = hour % 12
        if h == 0 { h = 12 }
        return String(format: "%d:%02d %@", h, minute, period)
    }
}

extension Recurrence {
    public func summary() -> String {
        switch self {
        case let .weekly(days, times):
            return "\(Self.daysPhrase(days)) at \(Self.timesPhrase(times))"
        case let .dates(days, times):
            let n = days.count
            return "\(n) date\(n == 1 ? "" : "s") at \(Self.timesPhrase(times))"
        case .unknown:
            return "Unsupported schedule"
        }
    }

    private static func timesPhrase(_ times: [TimeOfDay]) -> String {
        times.sorted().map { $0.displayString }.joined(separator: ", ")
    }

    private static func daysPhrase(_ days: Set<Weekday>) -> String {
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        if days == Set(Weekday.allCases) { return "Daily" }
        if days == weekdays { return "Weekdays" }
        if days == [.saturday, .sunday] { return "Weekends" }
        let names: [Weekday: String] = [
            .sunday: "Sun", .monday: "Mon", .tuesday: "Tue", .wednesday: "Wed",
            .thursday: "Thu", .friday: "Fri", .saturday: "Sat"
        ]
        return days.sorted().compactMap { names[$0] }.joined(separator: ", ")
    }
}
