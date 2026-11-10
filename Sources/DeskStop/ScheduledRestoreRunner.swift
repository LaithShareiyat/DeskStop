import AppKit
import DisplayCore
import SchedulingCore

/// Runs one fired schedule, applying the same guards as auto-restore.
struct ScheduledRestoreRunner {
    let presetStore: PresetStore
    let displayMonitor: DisplayMonitor
    let scheduleStore: ScheduleStore
    let undoStore: UndoSlotStore
    let arrangementApplier: DisplayArrangementApplier
    /// Title + body; AppDelegate routes this through the Show Notifications toggle.
    let notify: (String, String) -> Void
    /// Like `notify`, but with an Undo button.
    let notifyUndoable: (String, String) -> Void

    func run(_ schedule: Schedule) {
        // 1. Preset resolved? If gone, auto-disable so it stops erroring.
        guard let preset = presetStore.find(id: schedule.presetID) else {
            NSLog("DeskStop scheduled restore: preset missing, disabling '\(schedule.name)'")
            scheduleStore.setEnabled(id: schedule.id, false)
            return
        }
        // Apps open exactly when the layout itself says so (Open saved apps
        // in Settings → Layouts); a schedule has no say of its own.
        let plan = preset.restorePlan
        guard !plan.isEmpty else {
            notify("Schedule \u{201C}\(schedule.name)\u{201D} skipped",
                   "\u{201C}\(preset.name)\u{201D} has no restore options turned on.")
            return
        }
        // 2. Finder editable? Don't fight Sort By / Stacks — which only
        // matters when this restore writes icons.
        if plan.requiresEditableFinder {
            guard FinderSettings.read().positionsAreEditable else {
                NSLog("DeskStop scheduled restore skipped: positions not editable")
                notify("Schedule \u{201C}\(schedule.name)\u{201D} skipped",
                       "The desktop is sorted, so icons can't be moved.")
                return
            }
        }
        // 3. Display-config match? Otherwise positions belong to another screen setup.
        let current = displayMonitor.currentConfiguration
        guard preset.categoryKey == current.key else {
            notify("Schedule \u{201C}\(schedule.name)\u{201D} skipped",
                   "\u{201C}\(preset.name)\u{201D} is for \(preset.displaySetupName), but you're on \(current.displayName).")
            return
        }
        // 4. Reservation: a fire landing inside another restore's settle window
        // would write icons onto an unverified layout; see
        // DisplayArrangementApplier.reserve. A timing collision, not a broken
        // schedule, so don't auto-disable.
        guard DisplayArrangementApplier.reserve() else {
            NSLog("DeskStop scheduled restore skipped: a restore/undo is already in flight")
            notify("Schedule \u{201C}\(schedule.name)\u{201D} skipped",
                   "Another restore was in progress.")
            return
        }
        // 5. Restore icons; 6. optionally launch apps; 7. notify.
        undoStore.stashCurrentArrangement(displacedBy: preset.name, categoryKey: current.key,
                                          displayArrangement: DisplayArrangementApplier.undoArrangement(for: preset))
        arrangementApplier.applyThenSettle(for: preset) { outcome in
            if let notice = outcome.notice { notify(notice.title, notice.body) }
            finishScheduledRestore(preset, schedule, plan)
        }
    }

    private func finishScheduledRestore(_ preset: Preset, _ schedule: Schedule, _ plan: RestorePlan) {
        guard plan.writesIcons else {
            // Icon positions are switched off: the applier already moved the
            // displays, so only apps remain.
            if plan.launchesApps {
                RunningApps.launch(preset.apps ?? [])
            }
            NSLog("DeskStop scheduled restore '\(preset.name)' (\(schedule.name)): icons off, \(plan)")
            let title = "Restored \u{201C}\(preset.name)\u{201D}"
            let body = "Schedule \u{201C}\(schedule.name)\u{201D}. \(plan.nonIconSummary ?? "")"
            if plan.isUndoable {
                notifyUndoable(title, body)
            } else {
                notify(title, body)
            }
            return
        }
        do {
            let result = try IconArrangement.restore(positions: preset.positions)
            if plan.launchesApps {
                RunningApps.launch(preset.apps ?? [])
            }
            NSLog("DeskStop scheduled restore '\(preset.name)' (\(schedule.name)): \(result.succeeded)/\(result.attempted); missing=\(result.missing); movedAside=\(result.movedAside)")
            if let problem = result.problemTitle {
                notifyUndoable(problem,
                               (["Restored \u{201C}\(preset.name)\u{201D} for schedule \u{201C}\(schedule.name)\u{201D}."]
                                + result.notes).joined(separator: " "))
            } else {
                notifyUndoable("Restored \u{201C}\(preset.name)\u{201D}",
                               (["Schedule \u{201C}\(schedule.name)\u{201D}."] + result.notes).joined(separator: " "))
            }
        } catch {
            NSLog("DeskStop scheduled restore failed: \(error)")
            // Every other guard in this runner notifies; a throwing restore
            // (revoked Automation permission, Finder error) must not be the
            // one failure mode that stays silent forever.
            notify("Schedule \u{201C}\(schedule.name)\u{201D} failed",
                   "Icons couldn't be moved. \(error.localizedDescription)")
        }
    }
}
