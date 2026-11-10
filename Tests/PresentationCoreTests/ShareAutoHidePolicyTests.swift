import XCTest
@testable import PresentationCore

final class ShareAutoHidePolicyTests: XCTestCase {

    func test_hidesOnShareStart() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
    }

    func test_noActionWhileNotSharing() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: false), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: false), .none)
    }

    func test_neverShowsWhatItDidNotHide() {
        // Desktop was hidden manually before the share began.
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: true), .none)
        // Share ends: the manual hide must stay.
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
    }

    func test_showsAfterThresholdClearPolls() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .show)
    }

    func test_clearCounterResetsWhenSharingResumes() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
        // Two clear polls, then the share blips back on.
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: true), .none)
        // Countdown starts over: needs three fresh clear polls.
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: true), .show)
    }

    func test_userOverrideMidShareSuppressesRehideAndFinalShow() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
        // User manually shows the desktop while still sharing.
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .none)
        // No re-hide for the rest of this share session.
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .none)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .none)
        // Share ends: no show either (desktop is already visible).
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: false), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: false), .none)
        XCTAssertEqual(policy.tick(sharing: false, desktopHidden: false), .none)
        // A brand-new share session starts fresh and hides again.
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
    }

    // MARK: - Switching the feature off

    func test_switchingOffMidShareShowsWhatItHid() {
        // The setting is the only thing that brought the icons back, so
        // switching it off must not strand them hidden.
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: true), .none)
        XCTAssertEqual(policy.stop(desktopHidden: true), .show)
    }

    func test_switchingOffLeavesAManualHideAlone() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: true), .none)
        XCTAssertEqual(policy.stop(desktopHidden: true), .none)
    }

    func test_switchingOffAfterTheUserShowedTheIconsDoesNothing() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .none)   // overridden
        XCTAssertEqual(policy.stop(desktopHidden: false), .none)
    }

    func test_switchingOffWhenNothingWasHiddenDoesNothing() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.stop(desktopHidden: false), .none)
    }

    func test_switchingBackOnStartsFresh() {
        var policy = ShareAutoHidePolicy(unhideThreshold: 3)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .none)   // overridden
        _ = policy.stop(desktopHidden: false)
        // On again, still sharing: hides, rather than staying overridden.
        XCTAssertEqual(policy.tick(sharing: true, desktopHidden: false), .hide)
    }
}
