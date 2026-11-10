import XCTest
@testable import DisplayCore

/// Records every call so tests can assert on what the policy did — in
/// particular that it did *nothing* when it should not have.
private final class FakeDisplaySystem: DisplaySystem {
    var placements: [DisplayArrangement.Placement]
    /// The origins of every `apply` call, in order.
    var applyCalls: [[DisplayArrangement.Placement]] = []
    /// The modes of every `apply` call, in order.
    var modeCalls: [[String: DisplayMode]] = []
    /// What each display offers, by UUID.
    var offeredModes: [String: [DisplayMode]] = [:]
    /// Errors to throw from successive `apply` calls. `nil` succeeds.
    var errorsToThrow: [Error?] = []
    /// When true, a successful apply updates `placements` to what was applied.
    var applySucceedsVisibly = true
    /// Placements reported after the first apply, overriding `applySucceedsVisibly`.
    var placementsAfterApply: [DisplayArrangement.Placement]?
    /// When true, a thrown error still mutates `placements` via the normal
    /// merge before throwing -- models the real CoreGraphics failure mode
    /// where displays partially move before the transaction fails to commit.
    var throwAfterMutating = false

    struct Boom: Error, CustomStringConvertible {
        let description: String
    }

    init(placements: [DisplayArrangement.Placement]) {
        self.placements = placements
    }

    func currentPlacements() -> [DisplayArrangement.Placement] { placements }

    func availableModes(forDisplay uuid: String) -> [DisplayMode] { offeredModes[uuid] ?? [] }

    func apply(origins: [DisplayArrangement.Placement], modes: [String: DisplayMode]) throws {
        applyCalls.append(origins)
        modeCalls.append(modes)
        let error = errorsToThrow.isEmpty ? nil : errorsToThrow.removeFirst()
        if let error {
            if throwAfterMutating { merge(origins, modes) }
            throw error
        }
        if let override = placementsAfterApply {
            self.placements = override
            placementsAfterApply = nil
        } else if applySucceedsVisibly {
            merge(origins, modes)
        }
    }

    private func merge(_ origins: [DisplayArrangement.Placement], _ modes: [String: DisplayMode]) {
        // Displays not mentioned stay as they were; an origin moves a display
        // without touching its mode, and a mode changes nothing else.
        var merged = Dictionary(uniqueKeysWithValues: self.placements.map { ($0.uuid, $0) })
        for p in origins {
            let old = merged[p.uuid]
            merged[p.uuid] = .init(uuid: p.uuid, x: p.x, y: p.y, name: old?.name ?? p.name, mode: old?.mode)
        }
        for (uuid, mode) in modes {
            guard let old = merged[uuid] else { continue }
            merged[uuid] = .init(uuid: uuid, x: old.x, y: old.y, name: old.name, mode: mode)
        }
        // Sorted so iteration order is deterministic -- Dictionary.values
        // order is not guaranteed and every read path here should not rely
        // on it holding by accident.
        self.placements = Array(merged.values).sorted { $0.uuid < $1.uuid }
    }
}

final class ArrangementPolicyTests: XCTestCase {

    private let policy = ArrangementPolicy()

    private func p(_ uuid: String, _ x: Int32, _ y: Int32, name: String? = nil)
        -> DisplayArrangement.Placement {
        DisplayArrangement.Placement(uuid: uuid, x: x, y: y, name: name)
    }

    // MARK: - Preconditions

    func test_skipsWhenASavedDisplayIsNotAttached() {
        let system = FakeDisplaySystem(placements: [p("builtin", 0, 0)])
        let target = DisplayArrangement(placements: [
            p("builtin", -1920, 0),
            p("external", 0, 0, name: "DELL U2719D")
        ])

        let outcome = policy.apply(target: target, using: system)

        XCTAssertEqual(outcome, .skipped(reason: "DELL U2719D isn't connected"))
        XCTAssertTrue(system.applyCalls.isEmpty, "must not open a configuration transaction")
    }

    func test_skipReasonFallsBackToUUIDWhenNoNameWasCaptured() {
        let system = FakeDisplaySystem(placements: [p("builtin", 0, 0)])
        let target = DisplayArrangement(placements: [p("builtin", 0, 0), p("ghost", 1920, 0)])

        XCTAssertEqual(policy.apply(target: target, using: system),
                       .skipped(reason: "ghost isn't connected"))
    }

    // MARK: - Already correct (the loop defence)

    func test_alreadyCorrectDoesNotTouchTheDisplays() {
        let current = [p("builtin", 0, 0), p("external", 1920, 0)]
        let system = FakeDisplaySystem(placements: current)
        let target = DisplayArrangement(placements: current)

        let outcome = policy.apply(target: target, using: system)

        XCTAssertEqual(outcome, .alreadyCorrect)
        XCTAssertTrue(system.applyCalls.isEmpty,
                      "the loop defence depends on this making no calls")
    }

    func test_extraAttachedDisplayDoesNotDefeatTheAlreadyCorrectCheck() {
        // A third display the preset never mentioned must not force a reapply.
        let system = FakeDisplaySystem(placements: [
            p("builtin", 0, 0), p("external", 1920, 0), p("extra", -1920, 0)
        ])
        let target = DisplayArrangement(placements: [p("builtin", 0, 0), p("external", 1920, 0)])

        XCTAssertEqual(policy.apply(target: target, using: system), .alreadyCorrect)
        XCTAssertTrue(system.applyCalls.isEmpty)
    }

    // MARK: - Happy path

    func test_appliesRequestedPlacementsOnce() {
        let system = FakeDisplaySystem(placements: [p("builtin", 0, 0), p("external", -1920, 0)])
        let target = DisplayArrangement(placements: [p("builtin", 1920, 0), p("external", 0, 0)])

        let outcome = policy.apply(target: target, using: system)

        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(system.applyCalls.count, 1)
        XCTAssertEqual(system.applyCalls[0].map(\.uuid).sorted(), ["builtin", "external"])
    }

    func test_extraAttachedDisplayDoesNotFailVerification() {
        // Verification compares only the displays the target names.
        let system = FakeDisplaySystem(placements: [
            p("builtin", 0, 0), p("external", -1920, 0), p("extra", 3840, 0)
        ])
        let target = DisplayArrangement(placements: [p("builtin", 1920, 0), p("external", 0, 0)])

        XCTAssertEqual(policy.apply(target: target, using: system), .applied)
        XCTAssertEqual(system.applyCalls.count, 1, "must not roll back")
    }

    // MARK: - Failure and rollback

    func test_rollsBackWhenApplyThrows() {
        let snapshot = [p("builtin", 0, 0), p("external", -1920, 0)]
        let system = FakeDisplaySystem(placements: snapshot)
        system.errorsToThrow = [FakeDisplaySystem.Boom(description: "CGError 1004")]
        let target = DisplayArrangement(placements: [p("builtin", 1920, 0), p("external", 0, 0)])

        let outcome = policy.apply(target: target, using: system)

        guard case .rolledBack(let underlying) = outcome else {
            return XCTFail("expected .rolledBack, got \(outcome)")
        }
        XCTAssertTrue(underlying.contains("CGError 1004"))
        XCTAssertEqual(system.applyCalls.count, 2, "apply, then rollback")
        XCTAssertEqual(system.applyCalls[1].map(\.uuid).sorted(), ["builtin", "external"])
        XCTAssertEqual(Set(system.applyCalls[1].map { "\($0.uuid):\($0.x),\($0.y)" }),
                       Set(snapshot.map { "\($0.uuid):\($0.x),\($0.y)" }))
    }

    func test_rollsBackWhenVerificationDoesNotMatch() {
        let snapshot = [p("builtin", 0, 0), p("external", -1920, 0)]
        let system = FakeDisplaySystem(placements: snapshot)
        // Apply "succeeds" but the displays end up somewhere else entirely.
        system.placementsAfterApply = [p("builtin", 0, 0), p("external", 9999, 9999)]
        let target = DisplayArrangement(placements: [p("builtin", 1920, 0), p("external", 0, 0)])

        let outcome = policy.apply(target: target, using: system)

        guard case .rolledBack = outcome else {
            return XCTFail("expected .rolledBack, got \(outcome)")
        }
        XCTAssertEqual(system.applyCalls.count, 2, "apply, then rollback")
        XCTAssertEqual(Set(system.applyCalls[1].map { "\($0.uuid):\($0.x),\($0.y)" }),
                       Set(snapshot.map { "\($0.uuid):\($0.x),\($0.y)" }),
                       "rollback must restore the pre-apply snapshot, not the mangled post-apply state")
    }

    func test_rollbackRestoresPreApplySnapshotWhenApplyMutatesBeforeThrowing() {
        // Models a real CoreGraphics failure mode: the transaction partially
        // moves displays before failing to commit. Rollback must still target
        // the original pre-apply snapshot captured at the start of apply(),
        // not anything derived from the post-mutation state.
        let snapshot = [p("builtin", 0, 0), p("external", -1920, 0)]
        let system = FakeDisplaySystem(placements: snapshot)
        system.throwAfterMutating = true
        system.errorsToThrow = [FakeDisplaySystem.Boom(description: "commit failed mid-transaction")]
        let target = DisplayArrangement(placements: [p("builtin", 1920, 0), p("external", 0, 0)])

        let outcome = policy.apply(target: target, using: system)

        guard case .rolledBack = outcome else {
            return XCTFail("expected .rolledBack, got \(outcome)")
        }
        XCTAssertEqual(system.applyCalls.count, 2, "apply, then rollback")
        XCTAssertEqual(Set(system.applyCalls[1].map { "\($0.uuid):\($0.x),\($0.y)" }),
                       Set(snapshot.map { "\($0.uuid):\($0.x),\($0.y)" }),
                       "rollback call must carry the original pre-apply snapshot")
    }

    func test_rollbackNotConfirmedReturnsRollbackFailed() {
        // applyOrigins for the rollback call succeeds (no throw) but silently
        // doesn't take -- the displays are left in whatever state the first,
        // mangled apply produced. This must not be reported as .rolledBack.
        let snapshot = [p("builtin", 0, 0), p("external", -1920, 0)]
        let system = FakeDisplaySystem(placements: snapshot)
        system.applySucceedsVisibly = false
        system.placementsAfterApply = [p("builtin", 0, 0), p("external", 9999, 9999)]
        let target = DisplayArrangement(placements: [p("builtin", 1920, 0), p("external", 0, 0)])

        let outcome = policy.apply(target: target, using: system)

        guard case .rollbackFailed(let underlying) = outcome else {
            return XCTFail("expected .rollbackFailed, got \(outcome)")
        }
        XCTAssertTrue(underlying.contains("did not match"))
        XCTAssertEqual(system.applyCalls.count, 2, "apply, then a rollback attempt")
    }

    func test_reportsBothFailuresWhenRollbackAlsoFails() {
        let system = FakeDisplaySystem(placements: [p("builtin", 0, 0), p("external", -1920, 0)])
        system.errorsToThrow = [
            FakeDisplaySystem.Boom(description: "apply failed"),
            FakeDisplaySystem.Boom(description: "rollback failed")
        ]
        let target = DisplayArrangement(placements: [p("builtin", 1920, 0), p("external", 0, 0)])

        let outcome = policy.apply(target: target, using: system)

        guard case .rollbackFailed(let underlying) = outcome else {
            return XCTFail("expected .rollbackFailed, got \(outcome)")
        }
        XCTAssertTrue(underlying.contains("apply failed"))
        XCTAssertTrue(underlying.contains("rollback failed"))
    }

    // MARK: - Main display

    func test_movingTheMainDisplayIsAnOrdinaryApply() {
        // Main display is whichever sits at (0,0); there is no separate call.
        let system = FakeDisplaySystem(placements: [p("builtin", 0, 0), p("external", 1920, 0)])
        let target = DisplayArrangement(placements: [p("builtin", -1920, 0), p("external", 0, 0)])

        XCTAssertEqual(policy.apply(target: target, using: system), .applied)
        XCTAssertEqual(system.placements.first { $0.x == 0 && $0.y == 0 }?.uuid, "external")
    }

    func test_stackedDisplayWithNegativeYApplies() {
        let system = FakeDisplaySystem(placements: [p("builtin", 0, 0), p("above", 0, 1080)])
        let target = DisplayArrangement(placements: [p("builtin", 0, 0), p("above", 0, -1080)])

        XCTAssertEqual(policy.apply(target: target, using: system), .applied)
        XCTAssertEqual(system.placements.first { $0.uuid == "above" }?.y, -1080)
    }

    // MARK: - Resolution and refresh rate

    private func m(_ w: Int, _ h: Int, _ hz: Double) -> DisplayMode {
        DisplayMode(width: w, height: h, pixelWidth: w * 2, pixelHeight: h * 2, refreshRate: hz)
    }

    private func pm(_ uuid: String, _ x: Int32, _ y: Int32, _ mode: DisplayMode, name: String? = nil)
        -> DisplayArrangement.Placement {
        DisplayArrangement.Placement(uuid: uuid, x: x, y: y, name: name, mode: mode)
    }

    func test_modesAreAppliedWithThePositions() {
        let system = FakeDisplaySystem(placements: [pm("builtin", 0, 0, m(1512, 982, 120)),
                                                    pm("external", 1512, 0, m(1920, 1080, 60))])
        system.offeredModes = ["builtin": [m(1512, 982, 120), m(1800, 1169, 120)],
                               "external": [m(1920, 1080, 60), m(2560, 1440, 60)]]
        let target = DisplayArrangement(placements: [pm("builtin", 2560, 0, m(1800, 1169, 120)),
                                                     pm("external", 0, 0, m(2560, 1440, 60))])

        XCTAssertEqual(policy.apply(target: target, modes: true, using: system), .applied)
        XCTAssertEqual(system.applyCalls.count, 1, "positions and modes go in one transaction")
        XCTAssertEqual(system.modeCalls[0], ["builtin": m(1800, 1169, 120), "external": m(2560, 1440, 60)])
        XCTAssertEqual(system.placements.first { $0.uuid == "external" }?.x, 0)
        XCTAssertEqual(system.placements.first { $0.uuid == "builtin" }?.mode, m(1800, 1169, 120))
    }

    func test_modesAreLeftAloneUnlessAskedFor() {
        // A layout with modes saved but the option off moves displays only.
        let system = FakeDisplaySystem(placements: [pm("builtin", 0, 0, m(1512, 982, 120))])
        system.offeredModes = ["builtin": [m(1512, 982, 120), m(1800, 1169, 120)]]
        let target = DisplayArrangement(placements: [pm("builtin", 0, 0, m(1800, 1169, 120))])

        XCTAssertEqual(policy.apply(target: target, using: system), .alreadyCorrect)
        XCTAssertTrue(system.applyCalls.isEmpty)
    }

    func test_modesOnlyLeavesPositionsAlone() {
        let system = FakeDisplaySystem(placements: [pm("builtin", 0, 0, m(1512, 982, 120)),
                                                    pm("external", 1512, 0, m(1920, 1080, 60))])
        system.offeredModes = ["builtin": [m(1512, 982, 120), m(1800, 1169, 120)]]
        let target = DisplayArrangement(placements: [pm("builtin", 1920, 0, m(1800, 1169, 120)),
                                                     p("external", 0, 0)])

        XCTAssertEqual(policy.apply(target: target, positions: false, modes: true, using: system), .applied)
        XCTAssertEqual(system.applyCalls[0], [], "no display is moved")
        XCTAssertEqual(system.placements.first { $0.uuid == "external" }?.x, 1512)
    }

    func test_modesAlreadySetCountAsAlreadyCorrect() {
        // 59.94 Hz reported for a saved 60 Hz is the same mode.
        let system = FakeDisplaySystem(placements: [pm("external", 0, 0, m(1920, 1080, 59.94))])
        system.offeredModes = ["external": [m(1920, 1080, 59.94)]]
        let target = DisplayArrangement(placements: [pm("external", 0, 0, m(1920, 1080, 60))])

        XCTAssertEqual(policy.apply(target: target, modes: true, using: system), .alreadyCorrect)
        XCTAssertTrue(system.applyCalls.isEmpty)
    }

    func test_nearestRefreshRateStandsInForAnUnofferedOne() {
        let system = FakeDisplaySystem(placements: [pm("external", 0, 0, m(1920, 1080, 60))])
        system.offeredModes = ["external": [m(1920, 1080, 60), m(1920, 1080, 120)]]
        let target = DisplayArrangement(placements: [pm("external", 0, 0, m(1920, 1080, 144))])

        XCTAssertEqual(policy.apply(target: target, modes: true, using: system), .applied)
        XCTAssertEqual(system.placements.first?.mode, m(1920, 1080, 120))
    }

    func test_aResolutionTheDisplayCannotShowIsSkippedAndNamed() {
        let system = FakeDisplaySystem(placements: [pm("builtin", 0, 0, m(1512, 982, 120)),
                                                    pm("external", 1512, 0, m(1920, 1080, 60))])
        system.offeredModes = ["builtin": [m(1512, 982, 120), m(1800, 1169, 120)],
                               "external": [m(1920, 1080, 60)]]
        let target = DisplayArrangement(placements: [
            pm("builtin", 0, 0, m(1800, 1169, 120)),
            pm("external", 1512, 0, m(2560, 1440, 60), name: "DELL U2719D"),
        ])

        XCTAssertEqual(policy.apply(target: target, modes: true, using: system),
                       .partlyApplied(note: "DELL U2719D can't show 2560 × 1440, 60 Hz right now."))
        XCTAssertEqual(system.modeCalls[0], ["builtin": m(1800, 1169, 120)])
        XCTAssertEqual(system.placements.first { $0.uuid == "external" }?.mode, m(1920, 1080, 60))
    }

    func test_nothingLeftToDoButAnUnavailableModeIsASkip() {
        let system = FakeDisplaySystem(placements: [pm("external", 0, 0, m(1920, 1080, 60))])
        system.offeredModes = ["external": [m(1920, 1080, 60)]]
        let target = DisplayArrangement(placements: [pm("external", 0, 0, m(2560, 1440, 60), name: "Studio")])

        XCTAssertEqual(policy.apply(target: target, modes: true, using: system),
                       .skipped(reason: "Studio can't show 2560 × 1440, 60 Hz right now."))
        XCTAssertTrue(system.applyCalls.isEmpty)
    }

    func test_aModeAlreadyShownIsNotSetAgainWhenDisplaysMove() {
        // Setting a mode blanks the screen, so one already right is left out.
        let system = FakeDisplaySystem(placements: [pm("builtin", 0, 0, m(1512, 982, 120)),
                                                    pm("external", 1512, 0, m(1920, 1080, 59.94))])
        system.offeredModes = ["builtin": [m(1512, 982, 120)],
                               "external": [m(1920, 1080, 59.94), m(1920, 1080, 60)]]
        let target = DisplayArrangement(placements: [pm("builtin", 1920, 0, m(1512, 982, 120)),
                                                     pm("external", 0, 0, m(1920, 1080, 60))])

        XCTAssertEqual(policy.apply(target: target, modes: true, using: system), .applied)
        XCTAssertEqual(system.modeCalls[0], [:])
        XCTAssertEqual(system.placements.first { $0.uuid == "external" }?.x, 0)
    }

    func test_aModeThatDoesNotTakeRollsBackPositionsAndModes() {
        let system = FakeDisplaySystem(placements: [pm("builtin", 0, 0, m(1512, 982, 120)),
                                                    pm("external", 1512, 0, m(1920, 1080, 60))])
        system.offeredModes = ["builtin": [m(1512, 982, 120), m(1800, 1169, 120)],
                               "external": [m(1920, 1080, 60)]]
        // The transaction "succeeds" but the display comes back in another mode.
        system.placementsAfterApply = [pm("builtin", 2560, 0, m(1512, 982, 60)),
                                       pm("external", 0, 0, m(1920, 1080, 60))]
        let target = DisplayArrangement(placements: [pm("builtin", 2560, 0, m(1800, 1169, 120)),
                                                     pm("external", 0, 0, m(1920, 1080, 60))])

        let outcome = policy.apply(target: target, modes: true, using: system)

        guard case .rolledBack = outcome else { return XCTFail("expected rollback, got \(outcome)") }
        XCTAssertEqual(system.applyCalls.count, 2)
        XCTAssertEqual(system.modeCalls[1], ["builtin": m(1512, 982, 120)],
                       "only the display whose mode was changed is set back")
        XCTAssertEqual(system.placements.first { $0.uuid == "builtin" }?.mode, m(1512, 982, 120))
        XCTAssertEqual(system.placements.first { $0.uuid == "builtin" }?.x, 0)
    }

    func test_aFailedModeTransactionRollsBack() {
        let system = FakeDisplaySystem(placements: [pm("builtin", 0, 0, m(1512, 982, 120))])
        system.offeredModes = ["builtin": [m(1512, 982, 120), m(1800, 1169, 120)]]
        system.errorsToThrow = [FakeDisplaySystem.Boom(description: "commit failed"), nil]
        system.throwAfterMutating = true
        let target = DisplayArrangement(placements: [pm("builtin", 0, 0, m(1800, 1169, 120))])

        XCTAssertEqual(policy.apply(target: target, modes: true, using: system),
                       .rolledBack(underlying: "commit failed"))
        XCTAssertEqual(system.placements.first?.mode, m(1512, 982, 120))
    }
}
