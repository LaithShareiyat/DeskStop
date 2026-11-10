import XCTest
@testable import DisplayCore

final class RestoreFlagsTests: XCTestCase {

    // MARK: - Icon positions: absent means ON

    func testIconsAbsentFlagDefaultsToOn() {
        // Icons restore unless switched off; reading an absent flag as off would
        // silently neuter a layout.
        XCTAssertTrue(RestoreFlags.restoresIconPositions(stored: nil, hasPositions: true))
    }

    func testIconsExplicitFalseIsOff() {
        XCTAssertFalse(RestoreFlags.restoresIconPositions(stored: false, hasPositions: true))
    }

    func testIconsExplicitTrueIsOn() {
        XCTAssertTrue(RestoreFlags.restoresIconPositions(stored: true, hasPositions: true))
    }

    func testIconsNeedCapturedPositions() {
        XCTAssertFalse(RestoreFlags.restoresIconPositions(stored: true, hasPositions: false))
        XCTAssertFalse(RestoreFlags.restoresIconPositions(stored: nil, hasPositions: false))
    }

    // MARK: - Display arrangement: absent means OFF

    func testArrangementAbsentFlagDefaultsToOff() {
        XCTAssertFalse(RestoreFlags.restoresDisplayArrangement(stored: nil, hasArrangement: true))
    }

    func testArrangementExplicitTrueIsOn() {
        XCTAssertTrue(RestoreFlags.restoresDisplayArrangement(stored: true, hasArrangement: true))
    }

    func testArrangementNeedsCapturedArrangement() {
        XCTAssertFalse(RestoreFlags.restoresDisplayArrangement(stored: true, hasArrangement: false))
    }

    // MARK: - Display modes: absent means OFF

    func testModesAbsentFlagDefaultsToOff() {
        // Resolution is left alone unless the layout opts in.
        XCTAssertFalse(RestoreFlags.restoresDisplayModes(stored: nil, hasModes: true))
    }

    func testModesExplicitTrueIsOn() {
        XCTAssertTrue(RestoreFlags.restoresDisplayModes(stored: true, hasModes: true))
    }

    func testModesNeedCapturedModes() {
        // A layout with no captured modes has none to restore.
        XCTAssertFalse(RestoreFlags.restoresDisplayModes(stored: true, hasModes: false))
    }

    // MARK: - Apps: absent means OFF

    func testAppsAbsentFlagDefaultsToOff() {
        XCTAssertFalse(RestoreFlags.launchesApps(stored: nil, hasApps: true))
    }

    func testAppsExplicitTrueIsOn() {
        XCTAssertTrue(RestoreFlags.launchesApps(stored: true, hasApps: true))
    }

    func testAppsNeedSavedApps() {
        XCTAssertFalse(RestoreFlags.launchesApps(stored: true, hasApps: false))
    }

    // MARK: - The asymmetry itself

    func testIconsAreTheOnlyFlagThatDefaultsOn() {
        // Guards against a future "tidy-up" making all three consistent.
        XCTAssertTrue(RestoreFlags.restoresIconPositions(stored: nil, hasPositions: true))
        XCTAssertFalse(RestoreFlags.restoresDisplayArrangement(stored: nil, hasArrangement: true))
        XCTAssertFalse(RestoreFlags.restoresDisplayModes(stored: nil, hasModes: true))
        XCTAssertFalse(RestoreFlags.launchesApps(stored: nil, hasApps: true))
    }
}
