import XCTest
@testable import DisplayCore

final class DisplayModeTests: XCTestCase {
    private func mode(_ w: Int, _ h: Int, scale: Int = 2, _ hz: Double) -> DisplayMode {
        DisplayMode(width: w, height: h, pixelWidth: w * scale, pixelHeight: h * scale, refreshRate: hz)
    }

    // MARK: - Matching a saved mode to what the display offers now

    func testExactModeIsChosen() {
        let saved = mode(1512, 982, 120)
        let available = [mode(1512, 982, 60), mode(1512, 982, 120), mode(1800, 1169, 120)]
        XCTAssertEqual(DisplayMode.bestMatch(for: saved, in: available), mode(1512, 982, 120))
    }

    func testNearestRefreshRateWhenTheExactOneIsNotOffered() {
        // A dock that can't drive 144 Hz: the same resolution at the nearest rate.
        let saved = mode(2560, 1440, scale: 1, 144)
        let available = [mode(2560, 1440, scale: 1, 60), mode(2560, 1440, scale: 1, 120),
                         mode(1920, 1080, scale: 1, 144)]
        XCTAssertEqual(DisplayMode.bestMatch(for: saved, in: available), mode(2560, 1440, scale: 1, 120))
    }

    func testRefreshRateTieGoesToTheHigherRate() {
        let saved = mode(1920, 1080, scale: 1, 90)
        let available = [mode(1920, 1080, scale: 1, 60), mode(1920, 1080, scale: 1, 120)]
        XCTAssertEqual(DisplayMode.bestMatch(for: saved, in: available)?.refreshRate, 120)
    }

    func testScalingMustMatchNotJustTheSize() {
        // "Looks like 1920 × 1080" sharp (HiDPI) and blurry (1×) are different modes.
        let saved = mode(1920, 1080, scale: 2, 60)
        let available = [mode(1920, 1080, scale: 1, 60)]
        XCTAssertNil(DisplayMode.bestMatch(for: saved, in: available))
    }

    func testNoModeOfThatResolutionMeansNoMatch() {
        XCTAssertNil(DisplayMode.bestMatch(for: mode(3008, 1692, 60), in: [mode(2560, 1440, 60)]))
    }

    // MARK: - Same mode

    func testRefreshRatesWithinHalfAHertzAreTheSame() {
        // Displays report 59.94 for what System Settings calls 60 Hz.
        XCTAssertTrue(mode(1920, 1080, 59.94).isSame(as: mode(1920, 1080, 60)))
        XCTAssertFalse(mode(1920, 1080, 50).isSame(as: mode(1920, 1080, 60)))
        XCTAssertFalse(mode(1920, 1080, 60).isSame(as: mode(1920, 1200, 60)))
    }

    // MARK: - Description

    func testSummaryNamesSizeAndRate() {
        XCTAssertEqual(mode(1512, 982, 120).summary, "1512 × 982, 120 Hz")
        XCTAssertEqual(mode(1920, 1080, 59.94).summary, "1920 × 1080, 60 Hz")
    }

    func testSummaryLeavesOutAnUnreportedRate() {
        // Some built-in displays report a rate of 0.
        XCTAssertEqual(mode(1512, 982, 0).summary, "1512 × 982")
    }

    // MARK: - Saved files

    func testPlacementSavedBeforeModesStillDecodes() throws {
        let json = #"{"placements":[{"uuid":"A","x":0,"y":0,"name":"Built-in"}]}"#
        let arrangement = try JSONDecoder().decode(DisplayArrangement.self, from: Data(json.utf8))
        XCTAssertNil(arrangement.placements.first?.mode)
        XCTAssertFalse(arrangement.hasModes)
    }

    func testPlacementModeRoundTrips() throws {
        let original = DisplayArrangement(placements: [
            .init(uuid: "A", x: 0, y: 0, name: "Built-in", mode: mode(1512, 982, 120)),
        ])
        let decoded = try JSONDecoder().decode(DisplayArrangement.self,
                                               from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.placements.first?.mode, mode(1512, 982, 120))
        XCTAssertTrue(decoded.hasModes)
    }
}
