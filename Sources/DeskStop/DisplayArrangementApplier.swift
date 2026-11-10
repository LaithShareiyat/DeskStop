import AppKit
import DisplayCore

/// Applies a saved display arrangement, then waits for the new layout to
/// settle before the caller restores icon positions: changing the layout makes
/// macOS re-lay-out desktop icons, which would overwrite positions written
/// too early.
///
/// Only branches that changed a display wait; the rest complete synchronously.
final class DisplayArrangementApplier {
    private let policy = ArrangementPolicy()
    private let system = CoreGraphicsDisplaySystem()
    private let displayMonitor: DisplayMonitor

    /// Extra margin past the monitor's own debounce, so the settle timer for
    /// our own change has certainly elapsed before suppression lifts.
    private static let suppressionMargin: TimeInterval = 0.5

    /// The settle wait when resolutions may change. Longer than the monitor's:
    /// Finder re-lays out the desktop and an external display can take a second or
    /// two to show a picture again. Unmeasured.
    private static let modeSettleInterval: TimeInterval = 2.0

    /// Process-wide re-entrancy guard, shared by every instance (AppDelegate's,
    /// PresetActionsController's and the one in `RestorePresetIntent.perform`).
    /// A second apply landing inside the settle window would apply a layout the
    /// first icon write was never verified against and skew the undo stash.
    ///
    /// Not a lock: every entry point runs on the main thread.
    private static var busy = false

    /// Reserves the shared slot. Returns `false` (reserving nothing) if another
    /// cycle is in flight; the caller must then bail out without mutating anything.
    /// Reserve only on paths that go on to call `applyThenSettle`, the only
    /// thing that releases it.
    static func reserve() -> Bool {
        guard !busy else { return false }
        busy = true
        return true
    }

    /// Read-only peek at the slot, for a caller with side effects (the
    /// interactive restore launches apps) to run before `reserve()`.
    static var isBusy: Bool { busy }

    /// Released only from this type's own completion paths, never a caller's
    /// closure: a `weak self` guard there could skip the release and wedge every
    /// restore until relaunch.
    private static func release() {
        busy = false
    }

    init(displayMonitor: DisplayMonitor) {
        self.displayMonitor = displayMonitor
    }

    /// The displays as they are now: positions, with modes when `includingModes`.
    static func current(includingModes: Bool) -> DisplayArrangement {
        let now = DisplayArrangement(placements: CoreGraphicsDisplaySystem().currentPlacements())
        return includingModes ? now : now.withoutModes
    }

    /// What undo should put back after restoring `preset`: the displays as
    /// they are now, with their modes only when the restore sets modes, so
    /// undoing a positions-only restore never resets a resolution changed
    /// since. Nil when the restore leaves the displays alone.
    static func undoArrangement(for preset: Preset) -> DisplayArrangement? {
        guard preset.changesDisplays else { return nil }
        return current(includingModes: preset.restoresDisplayModes)
    }

    /// Apply a preset's saved arrangement and display modes, as far as it
    /// opts into each.
    func applyThenSettle(for preset: Preset,
                         completion: @escaping (ArrangementOutcome) -> Void) {
        guard preset.changesDisplays,
              let target = preset.displayArrangement else {
            NSLog("DeskStop display arrangement for '\(preset.name)': notRequested "
                  + "(flag=\(String(describing: preset.restoreDisplayArrangement)), "
                  + "modes=\(String(describing: preset.restoreDisplayModes)), "
                  + "captured=\(preset.displayArrangement != nil))")
            Self.release()
            completion(.notRequested)
            return
        }
        applyThenSettle(arrangement: target,
                        positions: preset.restoresDisplayArrangement,
                        modes: preset.restoresDisplayModes,
                        label: preset.name, completion: completion)
    }

    /// Apply a specific arrangement. Used by preset restore and by undo,
    /// which puts back modes too whenever the stashed arrangement has them.
    func applyThenSettle(arrangement: DisplayArrangement,
                         positions: Bool = true,
                         modes: Bool = false,
                         label: String,
                         completion: @escaping (ArrangementOutcome) -> Void) {
        // Suppress before touching anything: the notification can arrive
        // before CGCompleteDisplayConfiguration returns.
        let settle = modes ? Self.modeSettleInterval : DisplayMonitor.settleInterval
        displayMonitor.suppress(for: settle + Self.suppressionMargin)

        let outcome = policy.apply(target: arrangement, positions: positions, modes: modes, using: system)
        NSLog("DeskStop display arrangement for '\(label)': \(outcome)")

        let changedDisplays: Bool
        switch outcome {
        case .applied, .partlyApplied: changedDisplays = true
        default: changedDisplays = false
        }
        guard changedDisplays else {
            Self.release()
            completion(outcome)
            return
        }

        // Let the new layout settle before icon positions are written.
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            Self.release()
            completion(outcome)
        }
    }
}

extension ArrangementOutcome {
    /// The notification for a restore or undo whose displays didn't end up
    /// entirely as saved. Nil when there's nothing to say.
    var notice: (title: String, body: String)? {
        switch self {
        case .skipped(let reason):
            return ("Displays not changed", reason)
        case .partlyApplied(let note):
            return ("Some display settings not restored", note)
        case .rolledBack(let underlying):
            return ("Couldn't restore displays", "They were put back as they were. \(underlying)")
        case .rollbackFailed(let underlying):
            return ("Couldn't restore displays",
                    "They may not be as you expect. Check System Settings › Displays. \(underlying)")
        case .applied, .alreadyCorrect, .notRequested:
            return nil
        }
    }
}
