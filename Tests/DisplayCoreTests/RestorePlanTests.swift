import XCTest
@testable import DisplayCore

final class RestorePlanTests: XCTestCase {

    // MARK: - Finder guard

    func testIconWriteRequiresEditableFinder() {
        let plan = RestorePlan(writesIcons: true, movesDisplays: false, launchesApps: false)
        XCTAssertTrue(plan.requiresEditableFinder)
    }

    func testDisplayOnlyRestoreIgnoresFinderSorting() {
        // Finder's Sort By / Stacks blocks icon writes. It says nothing about
        // whether displays can move, so it must not block this restore.
        let plan = RestorePlan(writesIcons: false, movesDisplays: true, launchesApps: false)
        XCTAssertFalse(plan.requiresEditableFinder)
    }

    func testAppsOnlyRestoreIgnoresFinderSorting() {
        let plan = RestorePlan(writesIcons: false, movesDisplays: false, launchesApps: true)
        XCTAssertFalse(plan.requiresEditableFinder)
    }

    // MARK: - Nothing to do

    func testNothingSwitchedOnIsEmpty() {
        let plan = RestorePlan(writesIcons: false, movesDisplays: false, launchesApps: false)
        XCTAssertTrue(plan.isEmpty)
    }

    func testAnySinglePayloadIsNotEmpty() {
        XCTAssertFalse(RestorePlan(writesIcons: true, movesDisplays: false, launchesApps: false).isEmpty)
        XCTAssertFalse(RestorePlan(writesIcons: false, movesDisplays: true, launchesApps: false).isEmpty)
        XCTAssertFalse(RestorePlan(writesIcons: false, movesDisplays: false, launchesApps: true).isEmpty)
    }

    // MARK: - Undo

    func testAppsOnlyRestoreIsNotUndoable() {
        // Undo puts icons and displays back; it cannot un-launch an app.
        let plan = RestorePlan(writesIcons: false, movesDisplays: false, launchesApps: true)
        XCTAssertFalse(plan.isUndoable)
    }

    func testIconOrDisplayRestoreIsUndoable() {
        XCTAssertTrue(RestorePlan(writesIcons: true, movesDisplays: false, launchesApps: true).isUndoable)
        XCTAssertTrue(RestorePlan(writesIcons: false, movesDisplays: true, launchesApps: false).isUndoable)
    }

    // MARK: - Notification copy for restores that move no icons

    func testIconRestoreLeavesCopyToCaller() {
        let plan = RestorePlan(writesIcons: true, movesDisplays: true, launchesApps: true)
        XCTAssertNil(plan.nonIconSummary)
    }

    func testDisplayOnlySummary() {
        let plan = RestorePlan(writesIcons: false, movesDisplays: true, launchesApps: false)
        XCTAssertEqual(plan.nonIconSummary, "Restored displays only.")
    }

    func testDisplayAndAppsSummary() {
        let plan = RestorePlan(writesIcons: false, movesDisplays: true, launchesApps: true)
        XCTAssertEqual(plan.nonIconSummary, "Restored displays and opened apps.")
    }

    func testAppsOnlySummary() {
        let plan = RestorePlan(writesIcons: false, movesDisplays: false, launchesApps: true)
        XCTAssertEqual(plan.nonIconSummary, "Opened apps only.")
    }
}
