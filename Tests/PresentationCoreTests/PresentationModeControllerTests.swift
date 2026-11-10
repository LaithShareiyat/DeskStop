import XCTest
@testable import PresentationCore

/// Every present and dismiss across all overlays, in order.
private var events: [String] = []

private final class FakeOverlay: DesktopOverlay {
    static var count = 0
    let name: String
    var presented = 0
    var dismissed = 0
    init() { FakeOverlay.count += 1; name = "o\(FakeOverlay.count)" }
    func present() { presented += 1; events.append("present \(name)") }
    func dismiss() { dismissed += 1; events.append("dismiss \(name)") }
}

final class PresentationModeControllerTests: XCTestCase {
    private func make(screens: @escaping () -> [Int])
        -> (PresentationModeController<Int>, () -> [FakeOverlay]) {
        var created: [FakeOverlay] = []
        let controller = PresentationModeController<Int>(
            screens: screens,
            makeOverlay: { _ in let o = FakeOverlay(); created.append(o); return o })
        return (controller, { created })
    }

    func test_hide_createsAndShowsOneOverlayPerScreen() {
        let (c, created) = make(screens: { [1, 2, 3] })
        c.hide()
        XCTAssertTrue(c.isHidden)
        XCTAssertEqual(created().count, 3)
        XCTAssertTrue(created().allSatisfy { $0.presented == 1 })
    }

    func test_show_dismissesAllOverlays() {
        let (c, created) = make(screens: { [1, 2] })
        c.hide()
        c.show()
        XCTAssertFalse(c.isHidden)
        XCTAssertTrue(created().allSatisfy { $0.dismissed == 1 })
    }

    func test_hide_isIdempotent() {
        let (c, created) = make(screens: { [1, 2] })
        c.hide(); c.hide()
        XCTAssertEqual(created().count, 2)
    }

    func test_rebuildIfHidden_recreatesForChangedScreenSet() {
        var list = [1, 2]
        let (c, created) = make(screens: { list })
        c.hide()
        XCTAssertEqual(created().count, 2)
        list = [1]
        c.rebuildIfHidden()
        XCTAssertEqual(created().count, 3)            // 2 old + 1 new
        XCTAssertEqual(created()[0].dismissed, 1)     // old ones dismissed
        XCTAssertEqual(created()[1].dismissed, 1)
        XCTAssertEqual(created()[2].presented, 1)     // new one shown
    }

    func test_rebuildIfHidden_coversTheScreensBeforeUncoveringThem() {
        // Dismissing first would show the real icons for a moment, mid-share.
        FakeOverlay.count = 0
        let (c, _) = make(screens: { [1] })
        c.hide()
        events = []
        c.rebuildIfHidden()
        XCTAssertEqual(events, ["present o2", "dismiss o1"])
    }

    func test_rebuildIfHidden_whenShown_isNoop() {
        let (c, created) = make(screens: { [1, 2] })
        c.rebuildIfHidden()
        XCTAssertEqual(created().count, 0)
    }
}
