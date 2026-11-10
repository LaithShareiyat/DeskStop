import XCTest
@testable import DisplayCore

final class SuppressionWindowTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func test_notSuppressedInitially() {
        let window = SuppressionWindow()
        XCTAssertFalse(window.isSuppressed(now: t0))
    }

    func test_suppressedBeforeDeadline() {
        var window = SuppressionWindow()
        window.suppress(until: t0.addingTimeInterval(1))
        XCTAssertTrue(window.isSuppressed(now: t0))
    }

    func test_notSuppressedAtOrAfterDeadline() {
        var window = SuppressionWindow()
        window.suppress(until: t0)
        XCTAssertFalse(window.isSuppressed(now: t0))
        XCTAssertFalse(window.isSuppressed(now: t0.addingTimeInterval(1)))
    }

    func test_extendingLengthensTheWindow() {
        var window = SuppressionWindow()
        window.suppress(until: t0.addingTimeInterval(1))
        window.suppress(until: t0.addingTimeInterval(5))
        XCTAssertTrue(window.isSuppressed(now: t0.addingTimeInterval(3)))
    }

    func test_anEarlierDeadlineNeverShortensAnActiveWindow() {
        // Two overlapping applies must not let the second cut the first short,
        // which would let the first apply's events through.
        var window = SuppressionWindow()
        window.suppress(until: t0.addingTimeInterval(10))
        window.suppress(until: t0.addingTimeInterval(2))
        XCTAssertTrue(window.isSuppressed(now: t0.addingTimeInterval(5)))
    }
}
