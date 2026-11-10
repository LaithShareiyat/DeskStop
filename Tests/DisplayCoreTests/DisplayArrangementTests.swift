import XCTest
@testable import DisplayCore

final class DisplayArrangementTests: XCTestCase {

    private func placement(_ uuid: String, _ x: Int32, _ y: Int32, name: String? = nil)
        -> DisplayArrangement.Placement {
        DisplayArrangement.Placement(uuid: uuid, x: x, y: y, name: name)
    }

    func test_placementsAreSortedByUUID() {
        let a = DisplayArrangement(placements: [
            placement("ccc", 1920, 0),
            placement("aaa", 0, 0),
            placement("bbb", -1920, 0)
        ])
        XCTAssertEqual(a.placements.map(\.uuid), ["aaa", "bbb", "ccc"])
    }

    func test_equalityIsOrderInsensitive() {
        let a = DisplayArrangement(placements: [placement("aaa", 0, 0), placement("bbb", 1920, 0)])
        let b = DisplayArrangement(placements: [placement("bbb", 1920, 0), placement("aaa", 0, 0)])
        XCTAssertEqual(a, b)
    }

    func test_nameIsExcludedFromEquality() {
        // A monitor renamed between capture and restore is still the same monitor;
        // comparing on the name would cause spurious rollbacks.
        let a = DisplayArrangement(placements: [placement("aaa", 0, 0, name: "DELL U2719D")])
        let b = DisplayArrangement(placements: [placement("aaa", 0, 0, name: "Renamed Monitor")])
        XCTAssertEqual(a, b)
    }

    func test_mainDisplayIsTheOneAtOrigin() {
        let a = DisplayArrangement(placements: [
            placement("external", -1920, 0),
            placement("builtin", 0, 0)
        ])
        XCTAssertEqual(a.mainDisplayUUID, "builtin")
    }

    func test_mainDisplayIsNilWhenNoDisplayIsAtOrigin() {
        let a = DisplayArrangement(placements: [placement("external", 100, 100)])
        XCTAssertNil(a.mainDisplayUUID)
    }

    func test_codableRoundTripPreservesNegativeYForStackedDisplays() throws {
        // A display physically ABOVE the main one has negative Y in CG space.
        // This is the case a coordinate-space bug would break.
        let original = DisplayArrangement(placements: [
            placement("builtin", 0, 0, name: "Built-in"),
            placement("above", 0, -1080, name: "DELL U2719D")
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DisplayArrangement.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.placements.first { $0.uuid == "above" }?.y, -1080)
        XCTAssertEqual(decoded.placements.first { $0.uuid == "above" }?.name, "DELL U2719D")
    }

    func test_decodingSortsPlacements() throws {
        let json = """
        {"placements":[{"uuid":"zzz","x":0,"y":0},{"uuid":"aaa","x":1920,"y":0}]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(DisplayArrangement.self, from: json)
        XCTAssertEqual(decoded.placements.map(\.uuid), ["aaa", "zzz"])
    }
}
