import Foundation

/// A clock time, 0...23 hour and 0...59 minute.
public struct TimeOfDay: Codable, Equatable, Hashable, Comparable {
    public var hour: Int
    public var minute: Int
    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }
    /// Minutes since midnight, for ordering.
    public var minutesSinceMidnight: Int { hour * 60 + minute }
    public static func < (a: TimeOfDay, b: TimeOfDay) -> Bool {
        a.minutesSinceMidnight < b.minutesSinceMidnight
    }
}

/// Raw values match `Calendar`'s `.weekday` component (1 = Sunday ... 7 = Saturday).
public enum Weekday: Int, Codable, CaseIterable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
}

/// An absolute calendar date (no time component).
public struct CalendarDate: Codable, Equatable {
    public var year: Int
    public var month: Int
    public var day: Int
    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }
}

/// How a schedule repeats. `.unknown` is produced when decoding a recurrence
/// type written by a newer app version; it never fires.
public enum Recurrence: Equatable {
    case weekly(days: Set<Weekday>, times: [TimeOfDay])
    case dates(days: [CalendarDate], times: [TimeOfDay])
    case unknown
}

extension Recurrence: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, days, times
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .weekly(days, times):
            try c.encode("weekly", forKey: .type)
            try c.encode(days.sorted(), forKey: .days)
            try c.encode(times, forKey: .times)
        case let .dates(days, times):
            try c.encode("dates", forKey: .type)
            try c.encode(days, forKey: .days)
            try c.encode(times, forKey: .times)
        case .unknown:
            try c.encode("unknown", forKey: .type)
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "weekly":
            self = .weekly(days: Set(try c.decode([Weekday].self, forKey: .days)),
                           times: try c.decode([TimeOfDay].self, forKey: .times))
        case "dates":
            self = .dates(days: try c.decode([CalendarDate].self, forKey: .days),
                          times: try c.decode([TimeOfDay].self, forKey: .times))
        default:
            self = .unknown
        }
    }
}

/// One scheduled restore: a recurrence that fires a bound preset.
public struct Schedule: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var presetID: UUID
    public var enabled: Bool
    public var recurrence: Recurrence

    public init(id: UUID = UUID(),
                name: String,
                presetID: UUID,
                enabled: Bool = true,
                recurrence: Recurrence) {
        self.id = id
        self.name = name
        self.presetID = presetID
        self.enabled = enabled
        self.recurrence = recurrence
    }
}
