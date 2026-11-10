import AppKit
import UniformTypeIdentifiers
import DisplayCore

/// Per-layout operations: create, save, restore, rename, delete, shortcuts,
/// default, apps, import and export.
final class PresetActionsController: NSObject {
    private let presetStore: PresetStore
    private let hotkeyConfig: HotkeyConfigStore
    private let defaults: DefaultPresetStore
    private let displayMonitor: DisplayMonitor
    private let hotkeyManager: HotkeyManager
    private let undoStore: UndoSlotStore
    private let scheduleStore: ScheduleStore
    private lazy var arrangementApplier = DisplayArrangementApplier(displayMonitor: displayMonitor)
    /// Success-toast sink; AppDelegate routes it through Show Notifications.
    private let notify: (String, String) -> Void
    /// Like `notify`, but the notification carries an Undo button.
    private let notifyUndoable: (String, String) -> Void
    private let rebuildMenu: () -> Void
    /// Called after any hotkey mapping change so AppDelegate re-registers all.
    private let hotkeysChanged: () -> Void

    init(presetStore: PresetStore,
         hotkeyConfig: HotkeyConfigStore,
         defaults: DefaultPresetStore,
         displayMonitor: DisplayMonitor,
         hotkeyManager: HotkeyManager,
         undoStore: UndoSlotStore,
         scheduleStore: ScheduleStore,
         notify: @escaping (String, String) -> Void,
         notifyUndoable: @escaping (String, String) -> Void,
         rebuildMenu: @escaping () -> Void,
         hotkeysChanged: @escaping () -> Void) {
        self.presetStore = presetStore
        self.hotkeyConfig = hotkeyConfig
        self.defaults = defaults
        self.displayMonitor = displayMonitor
        self.hotkeyManager = hotkeyManager
        self.undoStore = undoStore
        self.scheduleStore = scheduleStore
        self.notify = notify
        self.notifyUndoable = notifyUndoable
        self.rebuildMenu = rebuildMenu
        self.hotkeysChanged = hotkeysChanged
        super.init()
    }

    /// Captures the live display arrangement: always when saving, and when
    /// restoring or undoing only if that would displace it.
    private func currentDisplayArrangement() -> DisplayArrangement {
        DisplayArrangement(placements: CoreGraphicsDisplaySystem().currentPlacements())
    }

    // MARK: - Create

    @objc func newPreset() {
        let config = displayMonitor.currentConfiguration
        guard let choice = Alerts.promptNewPreset(
            categoryLabel: config.displayName,
            defaultName: suggestedNewName(in: config.key)) else { return }
        let trimmed = choice.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if presetStore.nameExists(trimmed, inCategory: config.key) {
            Alerts.show(title: "That name is taken",
                        info: "There's already a layout called \u{201C}\(trimmed)\u{201D} for \(config.displayName).",
                        style: .warning)
            return
        }
        do {
            let snapshot = try IconArrangement.snapshot()
            // Everything is captured; the flags only govern what restore acts on.
            let preset = try presetStore.createNew(name: trimmed,
                                                   positions: snapshot.positions,
                                                   configuration: config,
                                                   restoreIconPositions: choice.restoreIcons,
                                                   displayArrangement: currentDisplayArrangement(),
                                                   restoreDisplayArrangement: choice.restoreArrangement,
                                                   restoreDisplayModes: choice.restoreModes)

            // Apps are picked, not captured wholesale. Cancelling the picker keeps
            // the layout.
            if choice.includeApps,
               let selected = AppPickerWindow.pick(),
               !selected.isEmpty {
                try presetStore.updateApps(id: preset.id, apps: selected)
                try presetStore.updateLaunchAppsOnRestore(id: preset.id, enabled: true)
            }

            // Read back what was stored: the picker may have been cancelled.
            let saved = presetStore.find(id: preset.id) ?? preset
            var parts: [String] = []
            if saved.restoresIconPositions { parts.append("icons") }
            if saved.restoresDisplayArrangement { parts.append("display arrangement") }
            if saved.restoresDisplayModes { parts.append("resolution and refresh rate") }
            if saved.launchesAppsOnRestore { parts.append("apps") }
            // Ticking only "Open saved apps" then cancelling leaves nothing on.
            notify("Created \u{201C}\(saved.name)\u{201D}",
                   parts.isEmpty
                       ? "It restores nothing yet. Turn options on in Settings › Layouts."
                       : "Restores \(parts.joined(separator: ", ")) for \(config.displayName).")
            rebuildMenu()
        } catch {
            Alerts.show(title: "Couldn't save the layout",
                        info: "\(error.localizedDescription)\n\n\(error)",
                        style: .warning)
        }
    }

    // MARK: - Save current arrangement (overwrite)

    @objc func saveCurrentArrangement(_ sender: NSMenuItem) {
        if let id = presetID(sender) { saveCurrentArrangement(id: id) }
    }

    func saveCurrentArrangement(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        let currentConfig = displayMonitor.currentConfiguration

        // Same-category save is the expected behavior, so no prompt.
        if preset.categoryKey == currentConfig.key {
            performSaveInPlace(presetID: id, preset: preset)
            return
        }

        // Saving to a different display setup's layout: confirm first.
        let twin = presetStore.list().first {
            $0.categoryKey == currentConfig.key &&
            $0.name.caseInsensitiveCompare(preset.name) == .orderedSame
        }
        let alert = NSAlert()
        alert.alertStyle = .informational
        if let twin = twin {
            alert.messageText = "Replace \u{201C}\(twin.name)\u{201D} for \(currentConfig.displayName)?"
            alert.informativeText = "\u{201C}\(preset.name)\u{201D} belongs to \(preset.displaySetupName), but you're on \(currentConfig.displayName). Your current desktop will replace the \u{201C}\(twin.name)\u{201D} layout for \(currentConfig.displayName). The one for \(preset.displaySetupName) stays as it is."
            alert.addButton(withTitle: "Replace")
        } else {
            alert.messageText = "Create \u{201C}\(preset.name)\u{201D} for \(currentConfig.displayName)?"
            alert.informativeText = "\u{201C}\(preset.name)\u{201D} belongs to \(preset.displaySetupName), but you're on \(currentConfig.displayName). Your current desktop will be saved as a new \u{201C}\(preset.name)\u{201D} layout for \(currentConfig.displayName). The one for \(preset.displaySetupName) stays as it is."
            alert.addButton(withTitle: "Create")
        }
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let snapshot = try IconArrangement.snapshot()
            if let twin = twin {
                try presetStore.updatePositions(id: twin.id, positions: snapshot.positions,
                                                displayArrangement: currentDisplayArrangement())
                notify("Replaced \u{201C}\(twin.name)\u{201D}",
                       "Saved your current desktop for \(currentConfig.displayName).")
            } else {
                // Inherit the source's opt-ins so the twin behaves like the original.
                let new = try presetStore.createNew(name: preset.name,
                                                    positions: snapshot.positions,
                                                    configuration: currentConfig,
                                                    restoreIconPositions: preset.restoreIconPositions,
                                                    displayArrangement: currentDisplayArrangement(),
                                                    restoreDisplayArrangement: preset.restoreDisplayArrangement,
                                                    restoreDisplayModes: preset.restoreDisplayModes)
                notify("Created \u{201C}\(new.name)\u{201D}",
                       "Saved your current desktop for \(currentConfig.displayName).")
            }
            rebuildMenu()
        } catch {
            Alerts.show(title: "Couldn't save the layout",
                        info: "\(error.localizedDescription)\n\n\(error)",
                        style: .warning)
        }
    }

    private func performSaveInPlace(presetID: UUID, preset: Preset) {
        do {
            let snapshot = try IconArrangement.snapshot()
            try presetStore.updatePositions(id: presetID, positions: snapshot.positions,
                                            displayArrangement: currentDisplayArrangement())
            notify("Replaced \u{201C}\(preset.name)\u{201D}",
                   "Saved your current desktop for \(preset.displaySetupName).")
            rebuildMenu()
        } catch {
            Alerts.show(title: "Couldn't save the layout",
                        info: "\(error.localizedDescription)\n\n\(error)",
                        style: .warning)
        }
    }

    // MARK: - Duplicate

    /// Copies a layout and puts the copy straight after it in its display
    /// setup's order. Returns the copy's id, so Settings can select it.
    @discardableResult
    func duplicatePreset(id: UUID) -> UUID? {
        guard let original = presetStore.find(id: id) else { return nil }
        do {
            let copy = try presetStore.duplicate(id: id)
            let ids = presetStore.presetsByCategory()
                .first { $0.key == original.categoryKey }?.presets.map(\.id) ?? []
            let others = ids.filter { $0 != copy.id }
            let after = others.firstIndex(of: id).map { $0 + 1 }
            let target = after.flatMap { others.indices.contains($0) ? others[$0] : nil }
            LayoutOrder.move(copy.id, before: target, in: ids, forSetup: original.categoryKey)
            notify("Duplicated \u{201C}\(original.name)\u{201D}",
                   "Saved as \u{201C}\(copy.name)\u{201D} for \(original.displaySetupName).")
            rebuildMenu()
            return copy.id
        } catch {
            Alerts.show(title: "Couldn't duplicate the layout",
                        info: error.localizedDescription, style: .warning)
            return nil
        }
    }

    // MARK: - Rename / delete

    @objc func renamePreset(_ sender: NSMenuItem) {
        if let id = presetID(sender) { renamePreset(id: id) }
    }

    func renamePreset(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        guard let newName = Alerts.prompt(title: "Rename Layout",
                                          message: "Enter a new name for \u{201C}\(preset.name)\u{201D}.",
                                          defaultValue: preset.name) else { return }
        renamePreset(id: id, to: newName)
    }

    /// Renames without prompting, for the name field in Settings → Layouts.
    /// An empty name or one already used on the same display setup is
    /// refused, the latter with an alert.
    func renamePreset(id: UUID, to newName: String) {
        guard let preset = presetStore.find(id: id) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != preset.name else { return }
        if presetStore.nameExists(trimmed, inCategory: preset.categoryKey, excluding: id) {
            Alerts.show(title: "That name is taken",
                        info: "There's already a layout called \u{201C}\(trimmed)\u{201D} for \(preset.displaySetupName).",
                        style: .warning)
            return
        }
        do {
            try presetStore.rename(id: id, to: trimmed)
            rebuildMenu()
        } catch {
            Alerts.show(title: "Couldn't rename the layout", info: error.localizedDescription, style: .warning)
        }
    }

    @objc func deletePreset(_ sender: NSMenuItem) {
        if let id = presetID(sender) { deletePreset(id: id) }
    }

    func deletePreset(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \u{201C}\(preset.name)\u{201D}?"
        alert.informativeText = "This deletes the layout for \(preset.displaySetupName) and its shortcut. Your desktop icons don't move."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? presetStore.delete(id: id)
        hotkeyConfig.clear(forPresetID: id)
        defaults.clearAnyReferencesTo(presetID: id)
        hotkeysChanged()
        rebuildMenu()
    }

    // MARK: - Hotkeys

    @objc func setHotkey(_ sender: NSMenuItem) {
        if let id = presetID(sender) { setHotkey(id: id) }
    }

    func setHotkey(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        let existing = hotkeyConfig.chord(forPresetID: id)
        let recorded = HotkeyRecorder.record(
            presetName: preset.name,
            existing: existing,
            collision: { [weak self] chord in
                guard let self = self else { return nil }
                guard let otherIDString = self.hotkeyConfig.presetBound(to: chord, excluding: id),
                      let otherID = UUID(uuidString: otherIDString),
                      let other = self.presetStore.find(id: otherID) else { return nil }
                return other.name
            }
        )
        if let chord = recorded {
            hotkeyConfig.set(chord, forPresetID: id)
            hotkeysChanged()
            rebuildMenu()
        }
    }

    @objc func removeHotkey(_ sender: NSMenuItem) {
        if let id = presetID(sender) { removeHotkey(id: id) }
    }

    func removeHotkey(id: UUID) {
        hotkeyConfig.clear(forPresetID: id)
        hotkeyManager.unregister(name: id.uuidString)
        rebuildMenu()
    }

    // MARK: - Default preset

    @objc func toggleDefaultPreset(_ sender: NSMenuItem) {
        if let id = presetID(sender) { toggleDefaultPreset(id: id) }
    }

    func toggleDefaultPreset(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        // Each display setup auto-restores one layout, so choosing this one
        // silently un-chooses another. Ask first.
        if let currentID = defaults.defaultPreset(forCategory: preset.categoryKey),
           currentID != id,
           let current = presetStore.find(id: currentID) {
            let alert = NSAlert()
            alert.messageText = "Auto-restore \u{201C}\(preset.name)\u{201D} instead?"
            alert.informativeText = "\u{201C}\(current.name)\u{201D} is restored when you switch to \(preset.displaySetupName). Only one layout per display setup can auto-restore, so it will stop."
            alert.addButton(withTitle: "Use \u{201C}\(preset.name)\u{201D}")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let nowDefault = defaults.toggleDefault(presetID: id, forCategory: preset.categoryKey)
        notify(nowDefault ? "\u{201C}\(preset.name)\u{201D} will auto-restore"
                          : "\u{201C}\(preset.name)\u{201D} won't auto-restore",
               nowDefault
                   ? "It's restored whenever you switch to \(preset.displaySetupName)."
                   : "No layout is set to auto-restore for \(preset.displaySetupName).")
        rebuildMenu()
    }

    // MARK: - Apps

    @objc func captureOpenApps(_ sender: NSMenuItem) {
        if let id = presetID(sender) { captureOpenApps(id: id) }
    }

    func captureOpenApps(id: UUID) {
        guard let selected = AppPickerWindow.pick(preselected: presetStore.find(id: id)?.apps ?? [])
        else { return } // nil == cancelled
        do {
            try presetStore.updateApps(id: id, apps: selected.isEmpty ? nil : selected)
            rebuildMenu()
        } catch {
            Alerts.show(title: "Couldn't save the apps", info: "\(error.localizedDescription)", style: .warning)
        }
    }

    @objc func clearSavedApps(_ sender: NSMenuItem) {
        if let id = presetID(sender) { clearSavedApps(id: id) }
    }

    func clearSavedApps(id: UUID) {
        try? presetStore.updateApps(id: id, apps: nil)
        rebuildMenu()
    }

    @objc func toggleLaunchAppsOnRestore(_ sender: NSMenuItem) {
        if let id = presetID(sender) { toggleLaunchAppsOnRestore(id: id) }
    }

    func toggleLaunchAppsOnRestore(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        try? presetStore.updateLaunchAppsOnRestore(id: id,
                                                   enabled: !(preset.launchAppsOnRestore ?? false))
        rebuildMenu()
    }

    @objc func toggleRestoreIconPositions(_ sender: NSMenuItem) {
        if let id = presetID(sender) { toggleRestoreIconPositions(id: id) }
    }

    func toggleRestoreIconPositions(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        // Negate the computed flag, not the stored optional: nil shows as on.
        try? presetStore.updateRestoreIconPositions(
            id: id,
            enabled: !preset.restoresIconPositions)
        rebuildMenu()
    }

    @objc func toggleRestoreDisplayArrangement(_ sender: NSMenuItem) {
        if let id = presetID(sender) { toggleRestoreDisplayArrangement(id: id) }
    }

    func toggleRestoreDisplayArrangement(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        try? presetStore.updateRestoreDisplayArrangement(
            id: id,
            enabled: !(preset.restoreDisplayArrangement ?? false))
        rebuildMenu()
    }

    func toggleRestoreDisplayModes(id: UUID) {
        guard let preset = presetStore.find(id: id) else { return }
        try? presetStore.updateRestoreDisplayModes(
            id: id,
            enabled: !(preset.restoreDisplayModes ?? false))
        rebuildMenu()
    }

    // MARK: - Restore

    @objc func restorePreset(_ sender: NSMenuItem) {
        if let id = presetID(sender) { restorePresetByID(id) }
    }

    /// The layout Restore Next Layout last landed on, per display setup, by id
    /// so reordering doesn't skip one.
    private var lastCycledByCategory: [String: UUID] = [:]
    /// Pending restore for the layout the switcher is showing; each press
    /// pushes it back, so only the layout the user stops on is restored.
    private var cycleRestore: DispatchWorkItem?
    /// How long after the last press the highlighted layout is restored.
    private static let cycleSettle: TimeInterval = 0.75

    /// Shows the switcher with the next layout highlighted, looping after the
    /// last, and restores it once the presses stop.
    @objc func cyclePresets() {
        let config = displayMonitor.currentConfiguration
        let key = config.key
        let presets = presetStore.presetsByCategory().first { $0.key == key }?.presets ?? []
        guard !presets.isEmpty else {
            notify("No layouts to restore", "There are no layouts for this display setup yet.")
            return
        }
        let lastIndex = lastCycledByCategory[key].flatMap { id in presets.firstIndex { $0.id == id } }
        let next = presets[((lastIndex ?? -1) + 1) % presets.count]
        lastCycledByCategory[key] = next.id

        LayoutSwitcherHUD.shared.show(
            setupName: config.displayName,
            setupSymbol: config.displaySymbol,
            tiles: presets.map {
                .init(id: $0.id, name: $0.name,
                      isAutoRestore: defaults.isDefault(presetID: $0.id, forCategory: key))
            },
            selected: next.id)

        cycleRestore?.cancel()
        let work = DispatchWorkItem { [weak self] in
            LayoutSwitcherHUD.shared.finish()
            self?.restorePresetByID(next.id)
        }
        cycleRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cycleSettle, execute: work)
    }

    func restorePresetByID(_ id: UUID) {
        guard let preset = presetStore.find(id: id) else {
            Alerts.show(title: "Layout not found",
                        info: "The layout was deleted before its shortcut was pressed.",
                        style: .warning)
            return
        }
        // Peek for a restore in flight before launching apps; `reserve()` stays below.
        guard !DisplayArrangementApplier.isBusy else {
            NSLog("DeskStop ignoring re-entrant restore of '\(preset.name)' — one is already in flight")
            return
        }
        let plan = preset.restorePlan

        // Launch apps even if icons can't be rearranged. Per-layout opt-in.
        if plan.launchesApps {
            RunningApps.launch(preset.apps ?? [])
        }

        // Display-only layouts have no icon work; skip only if nothing would happen.
        if plan.isEmpty {
            Alerts.show(title: "Nothing to restore",
                        info: "\u{201C}\(preset.name)\u{201D} has no restore options turned on. Turn some on in Settings › Layouts.")
            return
        }

        // Finder's Sort By / Stacks block icon writes, not display moves.
        if plan.requiresEditableFinder {
            let settings = FinderSettings.read()
            guard settings.positionsAreEditable else {
                let reason: String
                if settings.groupBy != "None" {
                    reason = "Stacks are on, so icons can't be moved. Right-click the desktop, turn off Use Stacks, then try again."
                } else {
                    reason = "The desktop is sorted by \u{201C}\(settings.arrangeBy)\u{201D}, so icons can't be moved. Right-click the desktop, choose Sort By › None, then try again."
                }
                Alerts.show(title: "Can't move icons", info: reason, style: .warning)
                return
            }
        }

        // Every restore reserves here, just before the first mutation, so a
        // rejected call changes nothing. The applier releases it.
        guard DisplayArrangementApplier.reserve() else {
            NSLog("DeskStop ignoring re-entrant restore of '\(preset.name)' — one is already in flight")
            return
        }

        undoStore.stashCurrentArrangement(displacedBy: preset.name,
                                          categoryKey: displayMonitor.currentConfiguration.key,
                                          displayArrangement: DisplayArrangementApplier.undoArrangement(for: preset))

        arrangementApplier.applyThenSettle(for: preset) { [weak self] outcome in
            guard let self else { return }
            if let notice = outcome.notice { self.notify(notice.title, notice.body) }
            self.finishRestore(preset)
        }
    }

    /// Posted after a layout is restored, with its id as `object`. The welcome
    /// tour listens for it.
    static let didRestoreLayout = Notification.Name("DeskStopDidRestoreLayout")

    private func finishRestore(_ preset: Preset) {
        defer { NotificationCenter.default.post(name: Self.didRestoreLayout, object: preset.id) }
        let plan = preset.restorePlan
        guard plan.writesIcons else {
            // Icons are off: the applier and app launch did everything. Undo can't
            // un-launch apps, so none is offered.
            let title = "Restored \u{201C}\(preset.name)\u{201D}"
            let body = plan.nonIconSummary ?? ""
            if plan.isUndoable {
                notifyUndoable(title, body)
            } else {
                notify(title, body)
            }
            return
        }
        do {
            let result = try IconArrangement.restore(positions: preset.positions)
            NSLog("DeskStop restore '\(preset.name)' (id=\(preset.id), category=\(preset.categoryLabel)): succeeded=\(result.succeeded)/\(result.attempted); missing=\(result.missing); failed=\(result.failed.map { "\($0.name)→\($0.reason)" }); movedAside=\(result.movedAside)")

            // Never killall Finder.
            if !result.hasProblems {
                let body = ([preset.displaySetupName] + result.notes).joined(separator: " ")
                notifyUndoable("Restored \u{201C}\(preset.name)\u{201D}", body)
            } else {
                var info = "Restored \u{201C}\(preset.name)\u{201D}, except for the items below."
                if !result.missing.isEmpty {
                    // One per line, so the user knows what to re-save.
                    let names = result.missing.prefix(10).map { "• \($0)" }.joined(separator: "\n")
                    let extra = result.missing.count > 10 ? "\n…and \(result.missing.count - 10) more" : ""
                    info += "\n\nNo longer on the desktop (deleted, renamed or moved):\n\(names)\(extra)"
                }
                if !result.failed.isEmpty {
                    let first = result.failed.prefix(5)
                        .map { "• \($0.name): \($0.reason)" }
                        .joined(separator: "\n")
                    let extra = result.failed.count > 5 ? "\n…and \(result.failed.count - 5) more" : ""
                    info += "\n\nFinder wouldn't move:\n\(first)\(extra)"
                }
                if !result.movedAside.isEmpty {
                    info += "\n\nMoved \(RestoreResult.quotedList(result.movedAside)) out of the way."
                }
                Alerts.show(title: result.problemTitle ?? "Couldn't restore every icon",
                            info: info, style: .warning)
            }
        } catch {
            NSLog("Restore failed: \(error)")
            Alerts.show(title: "Couldn't restore",
                        info: "\(error.localizedDescription)\n\n\(error)",
                        style: .warning)
        }
    }

    // MARK: - Undo

    /// Restores the arrangement the last restore displaced, stashing the live
    /// one first so a second undo toggles. A displaced display layout is put back
    /// through the applier before icons are written.
    @objc func undoLastRestore() {
        guard let snap = undoStore.load() else { return }
        let currentKey = displayMonitor.currentConfiguration.key
        guard snap.categoryKey == currentKey else {
            // Menu hides the item in this case; guard again for hotkey races.
            return
        }
        guard FinderSettings.read().positionsAreEditable else {
            Alerts.show(title: "Can't undo right now",
                        info: "The desktop is sorted or uses Stacks, so icons can't be moved.",
                        style: .warning)
            return
        }

        // Icon-only undo (no captured display arrangement) returns before the
        // applier, so check before reserving or the slot is never released.
        guard let target = snap.displayArrangement else {
            undoStore.stashCurrentArrangement(displacedBy: "Undo", categoryKey: currentKey,
                                              displayArrangement: nil)
            finishUndo(snap)   // no arrangement stored: behaves exactly as before
            return
        }

        // Reserve right before the stash so a rejected call mutates nothing; the
        // applier releases it.
        guard DisplayArrangementApplier.reserve() else {
            NSLog("DeskStop ignoring undo — a restore/undo is already in flight")
            return
        }

        // Modes go back only when the restore being undone changed them, and
        // the stash keeps them on the same terms, so undo toggles cleanly.
        undoStore.stashCurrentArrangement(displacedBy: "Undo", categoryKey: currentKey,
                                          displayArrangement: DisplayArrangementApplier.current(
                                              includingModes: target.hasModes))

        arrangementApplier.applyThenSettle(arrangement: target, modes: target.hasModes,
                                           label: "Undo") { [weak self] outcome in
            guard let self else { return }
            if let notice = outcome.notice { self.notify(notice.title, notice.body) }
            self.finishUndo(snap)
        }
    }

    private func finishUndo(_ snap: UndoSnapshot) {
        do {
            let result = try IconArrangement.restore(positions: snap.positions)
            NSLog("DeskStop undo restore: \(result.succeeded)/\(result.attempted)")
            notify("Undid restore",
                   "Your icons are back as they were.")
            rebuildMenu()
        } catch {
            Alerts.show(title: "Couldn't undo",
                        info: "\(error.localizedDescription)\n\n\(error)",
                        style: .warning)
        }
    }

    // MARK: - Import / export

    private var configService: ConfigBundleService {
        ConfigBundleService(presetStore: presetStore, hotkeyConfig: hotkeyConfig,
                            scheduleStore: scheduleStore, defaults: defaults)
    }

    @objc func exportPresets() {
        let bundle = configService.export()
        guard !bundle.presets.isEmpty || !bundle.schedules.isEmpty else {
            Alerts.show(title: "Nothing to export",
                        info: "You haven't saved any layouts or schedules yet.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "DeskStop Backup.json"
        panel.canCreateDirectories = true
        panel.title = "Export Backup"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bundle)
            try data.write(to: url, options: .atomic)
            Alerts.show(title: "Backup exported",
                        info: "\(Self.counted(bundle.presets.count, "layout")) and \(Self.counted(bundle.schedules.count, "schedule")), plus shortcuts, display setup names and settings, saved to \(url.lastPathComponent).")
        } catch {
            Alerts.show(title: "Couldn't export", info: error.localizedDescription, style: .warning)
        }
    }

    @objc func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Backup"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            if let bundle = try? decoder.decode(ConfigBundle.self, from: data),
               bundle.version >= 1, !bundle.presets.isEmpty || !bundle.schedules.isEmpty {
                let s = configService.merge(bundle)
                hotkeysChanged()
                rebuildMenu()
                Alerts.show(title: "Backup imported",
                            info: "\(Self.counted(s.presets, "layout")), \(Self.counted(s.schedules, "schedule")), \(Self.counted(s.hotkeys, "shortcut")) and \(Self.counted(s.setupNames, "display setup name")) were added, along with your settings.")
                return
            }
            Alerts.show(title: "Nothing to import",
                        info: "That file has no layouts or settings.")
        } catch {
            Alerts.show(title: "Couldn't import",
                        info: "That file couldn't be read.\n\n\(error.localizedDescription)",
                        style: .warning)
        }
    }

    // MARK: - Helpers

    private static func counted(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    /// The configuration a classic-menu item acts on. Every per-configuration
    /// `@objc` selector forwards to an `(id:)` twin, which is what the menu bar
    /// panel and Settings call directly.
    private func presetID(_ sender: NSMenuItem) -> UUID? {
        (sender.representedObject as? String).flatMap(UUID.init(uuidString:))
    }

    private func suggestedNewName(in categoryKey: String) -> String {
        let existing = Set(presetStore.list()
            .filter { $0.categoryKey == categoryKey }
            .map { $0.name })
        if !existing.contains("Layout") { return "Layout" }
        var i = 2
        while existing.contains("Layout \(i)") { i += 1 }
        return "Layout \(i)"
    }
}
