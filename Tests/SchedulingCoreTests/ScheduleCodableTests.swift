import XCTest
@testable import SchedulingCore

final class ScheduleCodableTests: XCTestCase {
    private func roundTrip(_ s: Schedule) throws -> Schedule {
        let data = try JSONEncoder().encode(s)
        return try JSONDecoder().decode(Schedule.self, from: data)
    }

    func test_weekly_roundTrips() throws {
        let s = Schedule(name: "Work",
                         presetID: UUID(),
                         enabled: true,
                         recurrence: .weekly(days: [.monday, .friday],
                                             times: [TimeOfDay(hour: 9, minute: 0)]))
        XCTAssertEqual(try roundTrip(s), s)
    }

    func test_unknownRecurrenceType_decodesToUnknown() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Future","presetID":"\(UUID().uuidString)",
         "enabled":true,"recurrence":{"type":"lunar"}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Schedule.self, from: json)
        XCTAssertEqual(decoded.recurrence, .unknown)
    }
}
