import XCTest
import CoreGraphics
@testable import DisplayCore

/// AppKit coordinates: origin bottom-left of the primary screen, y up.
final class StatusItemAnchorTests: XCTestCase {
    // The owner's layout: main 2560×1440, a notched laptop to the right and
    // lower, a portrait display to the left.
    private let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let laptop = CGRect(x: 2560, y: -173, width: 1512, height: 982)
    private let portrait = CGRect(x: -1440, y: -542, width: 1440, height: 2560)
    private var screens: [CGRect] { [main, laptop, portrait] }

    func testIconInAVisibleMenuBarIsUsedAsIs() {
        let icon = CGRect(x: 1825, y: 1416, width: 33, height: 24)
        XCTAssertEqual(StatusItemAnchor.anchorRect(iconRect: icon, screenFrames: screens), icon)
    }

    func testIconInAHiddenMenuBarIsPulledToTheTopOfItsScreen() {
        // A full-screen app's bar slides up out of view; its icon follows.
        let icon = CGRect(x: 1825, y: 1440 + 44, width: 33, height: 24)
        let anchor = StatusItemAnchor.anchorRect(iconRect: icon, screenFrames: screens)
        XCTAssertEqual(anchor, CGRect(x: 1825, y: 1440 - 24, width: 33, height: 24))
    }

    func testTheScreenIsTheOneWhoseMenuBarHoldsTheIcon() {
        // On the laptop's own menu bar, hidden.
        let icon = CGRect(x: 3800, y: 809 + 30, width: 33, height: 24)
        let anchor = StatusItemAnchor.anchorRect(iconRect: icon, screenFrames: screens)
        XCTAssertEqual(anchor.maxY, laptop.maxY)
        XCTAssertEqual(anchor.minX, 3800)
    }

    func testVerticallyStackedScreensPickTheNearerTop() {
        let lower = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let upper = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        let iconOnLower = CGRect(x: 1500, y: 1056, width: 30, height: 24)
        XCTAssertEqual(StatusItemAnchor.anchorRect(iconRect: iconOnLower, screenFrames: [lower, upper]),
                       iconOnLower)
        let hiddenOnUpper = CGRect(x: 1500, y: 2160 + 40, width: 30, height: 24)
        XCTAssertEqual(StatusItemAnchor.anchorRect(iconRect: hiddenOnUpper, screenFrames: [lower, upper]).maxY,
                       2160)
    }

    func testAnIconOutsideEveryScreenIsLeftAlone() {
        let icon = CGRect(x: 9000, y: 9000, width: 30, height: 24)
        XCTAssertEqual(StatusItemAnchor.anchorRect(iconRect: icon, screenFrames: screens), icon)
    }
}
