import Foundation

/// What happened when a preset's display arrangement was applied.
public enum ArrangementOutcome: Equatable {
    /// The preset does not opt in, or has no captured arrangement.
    case notRequested
    /// The displays were moved and the result verified.
    case applied
    /// Applied and verified, except a saved resolution a display can't show
    /// right now, named in `note`.
    case partlyApplied(note: String)
    /// The displays were already arranged this way; nothing was touched.
    case alreadyCorrect
    /// A precondition failed. Icon restore should still proceed.
    case skipped(reason: String)
    /// Applying or verifying failed and the previous arrangement was confirmed
    /// restored.
    case rolledBack(underlying: String)
    /// Applying failed and the previous arrangement could not be confirmed
    /// restored. The displays may be in an unexpected state, so the UI should
    /// point the user to System Settings.
    case rollbackFailed(underlying: String)
}

/// Decides whether and how to move the displays into a saved arrangement
/// and set their resolution and refresh rate.
///
/// Pure: every side effect goes through `DisplaySystem`. The sequence is
/// snapshot → precondition → choose modes → already-correct → apply →
/// verify → roll back on failure, so a failed apply never leaves a
/// half-applied layout. Positions and modes are asked for separately but
/// applied, verified and rolled back together.
public struct ArrangementPolicy {

    public init() {}

    /// - Parameters:
    ///   - positions: put each named display back where `target` has it.
    ///   - modes: set each named display back to its saved mode, where one
    ///     was saved, or the nearest the display offers now.
    public func apply(target: DisplayArrangement, positions: Bool = true, modes: Bool = false,
                      using system: DisplaySystem) -> ArrangementOutcome {
        let snapshot = DisplayArrangement(placements: system.currentPlacements())
        let attached = Set(snapshot.placements.map(\.uuid))

        // Every display the arrangement names must be present.
        if let missing = target.placements.first(where: { !attached.contains($0.uuid) }) {
            return .skipped(reason: "\(missing.name ?? missing.uuid) isn't connected")
        }

        // The mode to set on each display: the saved one, or the nearest it offers.
        // One it can't show is left alone and named in the outcome. One already
        // showing it is skipped, since setting a mode blanks the screen.
        var wantedModes: [String: DisplayMode] = [:]
        var unavailable: [String] = []
        if modes {
            for placement in target.placements {
                guard let saved = placement.mode else { continue }
                let offered = system.availableModes(forDisplay: placement.uuid)
                if let match = DisplayMode.bestMatch(for: saved, in: offered) {
                    let now = snapshot.placements.first { $0.uuid == placement.uuid }?.mode
                    if now?.isSame(as: match) != true { wantedModes[placement.uuid] = match }
                } else {
                    unavailable.append("\(placement.name ?? placement.uuid) can't show \(saved.summary) right now")
                }
            }
        }
        let note = unavailable.isEmpty ? nil : unavailable.joined(separator: "; ") + "."
        let origins = positions ? target.placements : []

        // Second layer of the feedback-loop defence: a display-change event that
        // escaped suppression finds the arrangement already correct and does nothing.
        if matches(snapshot, origins: origins, modes: wantedModes) {
            return note.map { .skipped(reason: $0) } ?? .alreadyCorrect
        }

        do {
            try system.apply(origins: origins, modes: wantedModes)
        } catch {
            return rollback(to: snapshot, changedModes: Array(wantedModes.keys),
                            using: system, because: "\(error)")
        }

        let after = DisplayArrangement(placements: system.currentPlacements())
        guard matches(after, origins: origins, modes: wantedModes) else {
            return rollback(to: snapshot, changedModes: Array(wantedModes.keys), using: system,
                            because: "displays did not match the requested arrangement after applying")
        }

        return note.map { .partlyApplied(note: $0) } ?? .applied
    }

    /// True when every display in `origins` sits where it should and every
    /// display in `modes` shows that mode.
    ///
    /// Not whole-arrangement equality: a display the preset never mentioned must
    /// not defeat the already-correct check or fail verification.
    private func matches(_ actual: DisplayArrangement,
                         origins: [DisplayArrangement.Placement],
                         modes: [String: DisplayMode]) -> Bool {
        for wanted in origins {
            guard let found = actual.placements.first(where: { $0.uuid == wanted.uuid }) else {
                return false
            }
            if found.x != wanted.x || found.y != wanted.y { return false }
        }
        for (uuid, wanted) in modes {
            guard let current = actual.placements.first(where: { $0.uuid == uuid })?.mode,
                  current.isSame(as: wanted) else { return false }
        }
        return true
    }

    /// Puts every display back where the snapshot had it, and the displays
    /// whose mode was changed back to their snapshot mode.
    private func rollback(to snapshot: DisplayArrangement,
                          changedModes: [String],
                          using system: DisplaySystem,
                          because reason: String) -> ArrangementOutcome {
        var previousModes: [String: DisplayMode] = [:]
        for uuid in changedModes {
            if let mode = snapshot.placements.first(where: { $0.uuid == uuid })?.mode {
                previousModes[uuid] = mode
            }
        }
        do {
            try system.apply(origins: snapshot.placements, modes: previousModes)
        } catch {
            return .rollbackFailed(underlying: "\(reason); rollback also failed: \(error)")
        }

        // A non-throwing apply isn't proof the displays moved back: re-read and
        // confirm before calling it restored.
        let after = DisplayArrangement(placements: system.currentPlacements())
        guard matches(after, origins: snapshot.placements, modes: previousModes) else {
            return .rollbackFailed(underlying: reason)
        }
        return .rolledBack(underlying: reason)
    }
}
