import Foundation

/// What one restore of a layout will actually do, resolved once from its
/// effective flags (`RestoreFlags`) and the calling path's own app-launch rule.
///
/// Every restore path (menu, hotkey, URL, auto-restore, schedule, App Intent)
/// asks this rather than re-deriving the guards inline.
///
/// Callers must check `isEmpty` and `requiresEditableFinder` *before* reserving
/// the restore slot (`DisplayArrangementApplier.reserve`): a reservation that
/// never reaches `applyThenSettle` is never released.
public struct RestorePlan: Equatable {
    public let writesIcons: Bool
    /// Moves the displays, sets their resolution, or both.
    public let movesDisplays: Bool
    public let launchesApps: Bool

    public init(writesIcons: Bool, movesDisplays: Bool, launchesApps: Bool) {
        self.writesIcons = writesIcons
        self.movesDisplays = movesDisplays
        self.launchesApps = launchesApps
    }

    /// Finder's Sort By / Stacks settings block icon writes and say nothing
    /// about whether displays can be moved or apps launched.
    public var requiresEditableFinder: Bool { writesIcons }

    /// Icon and display positions only fit the displays they were saved for;
    /// opening apps works on any.
    public var requiresMatchingDisplays: Bool { writesIcons || movesDisplays }

    /// Nothing would happen.
    public var isEmpty: Bool { !writesIcons && !movesDisplays && !launchesApps }

    /// Undo can put icons and displays back; it cannot un-launch an app.
    public var isUndoable: Bool { writesIcons || movesDisplays }

    /// Notification body for a restore that moved no icons. Nil when icons
    /// were written: those paths keep their own copy.
    public var nonIconSummary: String? {
        guard !writesIcons else { return nil }
        if movesDisplays {
            return launchesApps ? "Restored displays and opened apps." : "Restored displays only."
        }
        return launchesApps ? "Opened apps only." : nil
    }
}
