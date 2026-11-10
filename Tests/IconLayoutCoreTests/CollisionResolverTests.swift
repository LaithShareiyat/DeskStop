import XCTest
@testable import IconLayoutCore

final class CollisionResolverTests: XCTestCase {
    private let pitch = GridPitch(width: 100, height: 100)
    private let area = DesktopArea(minX: 0, minY: 0, maxX: 1000, maxY: 1000)

    private func spot(_ name: String, _ x: Double, _ y: Double) -> IconSpot {
        IconSpot(name: name, x: x, y: y)
    }

    func testNoOverlapMovesNothing() {
        let moves = CollisionResolver.relocations(
            restored: [spot("A", 500, 500)],
            others: [spot("New", 700, 500)],
            pitch: pitch, area: area)
        XCTAssertEqual(moves, [])
    }

    func testIconsOneSlotApartDoNotOverlap() {
        XCTAssertFalse(CollisionResolver.overlaps(spot("A", 500, 500), spot("B", 600, 500), pitch: pitch))
        XCTAssertTrue(CollisionResolver.overlaps(spot("A", 500, 500), spot("B", 560, 530), pitch: pitch))
    }

    func testOverlappingIconMovesToAnAdjacentFreeSlot() {
        let moves = CollisionResolver.relocations(
            restored: [spot("A", 500, 500)],
            others: [spot("New", 500, 500)],
            pitch: pitch, area: area)
        XCTAssertEqual(moves.count, 1)
        let moved = moves[0]
        XCTAssertEqual(moved.name, "New")
        XCTAssertFalse(CollisionResolver.overlaps(moved, spot("A", 500, 500), pitch: pitch))
        // One slot away, on a side rather than a corner.
        XCTAssertEqual(abs(moved.x - 500) + abs(moved.y - 500), 100)
    }

    func testTiesBreakDeterministically() {
        // All four sides are free and equally near. Ties break on x, then y,
        // so the left slot wins.
        let moves = CollisionResolver.relocations(
            restored: [spot("A", 500, 500)],
            others: [spot("New", 500, 500)],
            pitch: pitch, area: area)
        XCTAssertEqual(moves, [spot("New", 400, 500)])
    }

    func testSkipsOccupiedSlots() {
        let restored = [spot("A", 500, 500), spot("B", 400, 500), spot("C", 600, 500), spot("D", 500, 400)]
        let moves = CollisionResolver.relocations(
            restored: restored,
            others: [spot("New", 500, 500)],
            pitch: pitch, area: area)
        XCTAssertEqual(moves, [spot("New", 500, 600)])
    }

    func testIconsThatStayPutAlsoBlockSlots() {
        let moves = CollisionResolver.relocations(
            restored: [spot("A", 500, 500)],
            others: [spot("New", 500, 500), spot("Old", 400, 500)],
            pitch: pitch, area: area)
        XCTAssertEqual(moves, [spot("New", 500, 400)])
    }

    func testTwoCollidingIconsGetDifferentSlots() {
        let moves = CollisionResolver.relocations(
            restored: [spot("A", 500, 500)],
            others: [spot("New1", 500, 500), spot("New2", 510, 505)],
            pitch: pitch, area: area)
        XCTAssertEqual(moves.count, 2)
        XCTAssertFalse(CollisionResolver.overlaps(moves[0], moves[1], pitch: pitch))
    }

    func testStaysInsideTheArea() {
        // Restored icon in the top-left corner: left and up are off the desktop.
        let moves = CollisionResolver.relocations(
            restored: [spot("A", 0, 0)],
            others: [spot("New", 0, 0)],
            pitch: pitch, area: area)
        XCTAssertEqual(moves.count, 1)
        XCTAssertGreaterThanOrEqual(moves[0].x, 0)
        XCTAssertGreaterThanOrEqual(moves[0].y, 0)
    }

    func testFullDesktopLeavesTheIconWhereItIs() {
        let tiny = DesktopArea(minX: 500, minY: 500, maxX: 500, maxY: 500)
        let moves = CollisionResolver.relocations(
            restored: [spot("A", 500, 500)],
            others: [spot("New", 500, 500)],
            pitch: pitch, area: tiny)
        XCTAssertEqual(moves, [])
    }

    func testOverlapsBetweenUnrestoredIconsAreLeftAlone() {
        let moves = CollisionResolver.relocations(
            restored: [spot("A", 100, 100)],
            others: [spot("X", 500, 500), spot("Y", 500, 500)],
            pitch: pitch, area: area)
        XCTAssertEqual(moves, [])
    }
}
