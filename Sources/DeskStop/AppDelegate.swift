import AppKit
import Carbon.HIToolbox
import DisplayCore
import PresentationCore
import ServiceManagement

/// App lifecycle, status item, hotkey registration, display-change auto-restore,
/// and the app-level menu toggles. Menu construction lives in `MenuBuilder`;
/// per-preset operations live in `PresetActionsController`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    /// The classic menu, shown on right-click (or control-click). It is never
    /// attached to the status item for good: left-click opens the panel.
    private let appMenu = NSMenu()
    private let displayMonitor = DisplayMonitor()
    private lazy var arrangementApplier = DisplayArrangementApplier(displayMonitor: displayMonitor)
    private let hotkeyManager = HotkeyManager()
    private let presetStore = PresetStore()
    private let hotkeyConfig = HotkeyConfigStore()
    private let defaults = DefaultPresetStore()
    private let scheduleStore = ScheduleStore()
    private let undoStore = UndoSlotStore()
    private lazy var scheduledRunner = ScheduledRestoreRunner(
        presetStore: presetStore,
        displayMonitor: displayMonitor,
        scheduleStore: scheduleStore,
        undoStore: undoStore,
        arrangementApplier: arrangementApplier,
        notify: { [weak self] title, body in
            self?.notifySuccess(title: title, body: body)
        },
        notifyUndoable: { [weak self] title, body in
            self?.notifySuccess(title: title, body: body, undoable: true)
        })
    private lazy var scheduler = Scheduler(
        store: scheduleStore,
        fire: { [weak self] schedule in
            DispatchQueue.main.async { self?.scheduledRunner.run(schedule) }
        })
    /// Hides desktop icons behind per-screen overlay windows (presentation mode).
    private lazy var presentation = PresentationModeController<NSScreen>(
        screens: { NSScreen.screens },
        makeOverlay: { screen in
            DesktopOverlayWindow(screen: screen, picture: UserDefaults.standard.hiddenIconsPictureInUse)
        })
    private lazy var presetActions = PresetActionsController(
        presetStore: presetStore,
        hotkeyConfig: hotkeyConfig,
        defaults: defaults,
        displayMonitor: displayMonitor,
        hotkeyManager: hotkeyManager,
        undoStore: undoStore,
        scheduleStore: scheduleStore,
        notify: { [weak self] title, body in
            self?.notifySuccess(title: title, body: body)
        },
        notifyUndoable: { [weak self] title, body in
            self?.notifySuccess(title: title, body: body, undoable: true)
        },
        rebuildMenu: { [weak self] in self?.rebuildMenu() },
        hotkeysChanged: { [weak self] in self?.registerAllHotkeys() })
    private lazy var menuBuilder = MenuBuilder(
        presetStore: presetStore,
        hotkeyConfig: hotkeyConfig,
        defaults: defaults,
        displayMonitor: displayMonitor,
        scheduler: scheduler,
        undoStore: undoStore,
        isDesktopHidden: { [weak self] in self?.presentation.isHidden ?? false },
        appTarget: self,
        presetTarget: presetActions)
    /// Cached login-item state; SMAppService.status is a blocking XPC call,
    /// so it's read once at startup and refreshed only when toggled.
    private lazy var startAtLoginEnabled = SMAppService.mainApp.status == .enabled
    /// What the panel and Settings show, re-read from the stores on every
    /// `rebuildMenu()`.
    private lazy var model = AppModel(source: PanelSnapshotSource(
        presetStore: presetStore,
        hotkeyConfig: hotkeyConfig,
        defaults: defaults,
        displayMonitor: displayMonitor,
        scheduler: scheduler,
        scheduleStore: scheduleStore,
        undoStore: undoStore,
        isDesktopHidden: { [weak self] in self?.presentation.isHidden ?? false },
        isStartAtLoginEnabled: { [weak self] in self?.startAtLoginEnabled ?? false }
    ).make)
    private lazy var uiActions: UIActions = {
        let actions = UIActions(app: self, presets: presetActions)
        actions.closePanel = { [weak self] in self?.panel.close() }
        actions.refresh = { [weak self] in self?.model.refresh() }
        return actions
    }()
    /// The menu bar panel, opened by left-clicking the status item.
    private lazy var panel = MenuPanelController(model: model, actions: uiActions)
    private lazy var urlHandler = URLCommandHandler(
        presetStore: presetStore,
        displayMonitor: displayMonitor,
        restore: { [weak self] id in self?.presetActions.restorePresetByID(id) },
        hideIcons: { [weak self] in
            guard let self, !self.presentation.isHidden else { return }
            self.toggleHideDesktop()
        },
        showIcons: { [weak self] in
            guard let self, self.presentation.isHidden else { return }
            self.toggleHideDesktop()
        },
        toggleIcons: { [weak self] in self?.toggleHideDesktop() },
        openSettings: { [weak self] page in self?.showSettings(page: page) })
    private let screenShareMonitor = ScreenShareMonitor()
    private let updateChecker = UpdateChecker()
    /// Hide/show decisions for screen-share auto-hide (EXPERIMENTAL).
    private var shareHidePolicy = ShareAutoHidePolicy()
    /// Last seen display configuration, so a redundant `onChange` doesn't
    /// restore twice.
    private var lastSeenConfigurationKey: String?
    /// URLs can arrive before applicationDidFinishLaunching when a URL
    /// cold-launches the app; buffer them until launch setup has run.
    private var launchCompleted = false
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearanceMode.applyStored()
        setupStatusItem()
        lastSeenConfigurationKey = displayMonitor.currentConfiguration.key
        displayMonitor.start()
        displayMonitor.onChange = { [weak self] in
            DispatchQueue.main.async { self?.handleDisplayChange() }
        }
        registerAllHotkeys()
        scheduler.start()
        screenShareMonitor.onTick = { [weak self] sharing in
            self?.handleShareTick(sharing: sharing)
        }
        if UserDefaults.standard.hideIconsWhenScreenSharing {
            screenShareMonitor.start()
        }
        Notifier.shared.onUndo = { [weak self] in self?.presetActions.undoLastRestore() }
        // Ask every launch: the system prompts once, and the only other request
        // lives in onboarding, which never reruns.
        Notifier.shared.requestAuthorization()
        updateChecker.start()
        if !UserDefaults.standard.hasCompletedOnboarding {
            // The tour starts with Finder access, which saving and restoring
            // need; it isn't modal, since its steps happen on the desktop.
            DispatchQueue.main.async { [weak self] in self?.showWelcome() }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        launchCompleted = true
        let queued = pendingURLs
        pendingURLs = []
        queued.forEach { urlHandler.handle($0) }
    }

    /// `deskstop://` automation URLs (Shortcuts Focus automations,
    /// Raycast, Alfred, scripts). Registered via CFBundleURLTypes.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard launchCompleted else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        urls.forEach { urlHandler.handle($0) }
    }

    /// Rebuild overlay windows for the current screen set when displays
    /// change (dock/undock/resolution). Only matters while presentation mode
    /// is on.
    @objc private func screenParamsChanged() {
        presentation.rebuildIfHidden()
    }

    /// Spaces can each have their own wallpaper, and a wallpaper cover shows
    /// the one that was showing when it went up. A chosen picture is the
    /// same on every Space, so it's left alone.
    @objc private func activeSpaceChanged() {
        guard UserDefaults.standard.hiddenIconsPictureInUse == nil else { return }
        presentation.rebuildIfHidden()
    }

    /// Display arrangement changed (dock, undock, resolution change, etc.).
    /// Refreshes the menu and — if auto-restore is enabled and the new
    /// configuration has a designated default — runs that preset.
    private func handleDisplayChange() {
        let newConfig = displayMonitor.currentConfiguration
        let oldKey = lastSeenConfigurationKey
        lastSeenConfigurationKey = newConfig.key
        rebuildMenu()

        // Auto-restore is on for a display setup exactly when one of its
        // layouts is chosen for it (Settings → Layouts → Use for auto-restore).
        guard newConfig.key != oldKey,
              let defaultID = defaults.defaultPreset(forCategory: newConfig.key),
              let preset = presetStore.find(id: defaultID),
              !preset.restorePlan.isEmpty
        else { return }
        let plan = preset.restorePlan

        // Don't fight Sort By / Stacks: notify silently, never a modal mid-task.
        // Only icon writes care, so display-only layouts proceed.
        if plan.requiresEditableFinder {
            let settings = FinderSettings.read()
            guard settings.positionsAreEditable else {
                NSLog("DeskStop auto-restore skipped: positions not editable for \(newConfig.label)")
                notifySuccess(title: "Auto-restore of \u{201C}\(preset.name)\u{201D} skipped",
                              body: "The desktop is sorted, so icons can't be moved.")
                return
            }
        }

        // A dock/undock inside another restore's settle window would write icons
        // unverified (see DisplayArrangementApplier.reserve). Silent on rejection.
        guard DisplayArrangementApplier.reserve() else {
            NSLog("DeskStop auto-restore skipped: a restore/undo is already in flight")
            return
        }

        undoStore.stashCurrentArrangement(displacedBy: preset.name, categoryKey: newConfig.key,
                                          displayArrangement: DisplayArrangementApplier.undoArrangement(for: preset))
        arrangementApplier.applyThenSettle(for: preset) { [weak self] outcome in
            guard let self else { return }
            if let notice = outcome.notice {
                self.notifySuccess(title: notice.title, body: notice.body)
            }
            self.finishAutoRestore(preset, newConfig)
        }
    }

    private func finishAutoRestore(_ preset: Preset, _ newConfig: DisplayConfiguration) {
        let plan = preset.restorePlan
        guard plan.writesIcons else {
            // Icon positions are switched off for this configuration: the
            // applier has already moved the displays, so only apps remain.
            if plan.launchesApps {
                RunningApps.launch(preset.apps ?? [])
            }
            NSLog("DeskStop auto-restore '\(preset.name)' for \(newConfig.label): icons off, \(plan)")
            notifySuccess(title: "Auto-restored \u{201C}\(preset.name)\u{201D}",
                          body: "Displays changed to \(newConfig.displayName). \(plan.nonIconSummary ?? "")",
                          undoable: plan.isUndoable)
            return
        }
        do {
            let result = try IconArrangement.restore(positions: preset.positions)
            if plan.launchesApps {
                RunningApps.launch(preset.apps ?? [])
            }
            NSLog("DeskStop auto-restore '\(preset.name)' for \(newConfig.label): \(result.succeeded)/\(result.attempted); missing=\(result.missing); movedAside=\(result.movedAside)")
            // A problem leads the title so it reads at a glance in the banner;
            // the configuration's name moves into the body.
            if let problem = result.problemTitle {
                notifySuccess(
                    title: problem,
                    body: (["Auto-restored \u{201C}\(preset.name)\u{201D} for \(newConfig.displayName)."]
                           + result.notes).joined(separator: " "),
                    undoable: true
                )
            } else {
                notifySuccess(
                    title: "Auto-restored \u{201C}\(preset.name)\u{201D}",
                    body: (["Displays changed to \(newConfig.displayName)."] + result.notes).joined(separator: " "),
                    undoable: true
                )
            }
        } catch {
            NSLog("DeskStop auto-restore failed: \(error)")
            notifySuccess(title: "Couldn't auto-restore \u{201C}\(preset.name)\u{201D}",
                          body: "Icons couldn't be moved. \(error.localizedDescription)")
        }
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.statusBarIcon(hidden: presentation.isHidden)
        statusItem.button?.toolTip = "DeskStop"
        appMenu.delegate = self
        // Left-click opens the panel; right- or control-click opens the
        // classic menu, which still offers every action. The menu is attached
        // only transiently for that click.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        rebuildMenu()
    }

    /// Both glyphs are drawn into one canvas: their sizes differ and the status
    /// item sizes to its image, so a swap away from the menu bar could clip it.
    private static let statusIconCanvas = NSSize(width: 24, height: 18)

    static func statusBarIcon(hidden: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        // eye.slash while presentation mode hides the desktop, so the menu bar
        // reflects that icons are currently hidden; the grid otherwise.
        let name = hidden ? "eye.slash" : "square.grid.3x3"
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config),
              symbol.size.width > 0, symbol.size.height > 0 else { return nil }
        let canvas = statusIconCanvas
        let scale = min(1, canvas.width / symbol.size.width, canvas.height / symbol.size.height)
        let drawSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let image = NSImage(size: canvas, flipped: false) { rect in
            symbol.draw(in: NSRect(x: rect.midX - drawSize.width / 2,
                                   y: rect.midY - drawSize.height / 2,
                                   width: drawSize.width, height: drawSize.height),
                        from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = hidden ? "DeskStop, icons hidden" : "DeskStop"
        return image
    }

    /// Refresh the status-bar glyph to match presentation-mode state.
    private func updateStatusIcon() {
        statusItem.button?.image = Self.statusBarIcon(hidden: presentation.isHidden)
        statusItem.button?.needsDisplay = true
    }

    /// Re-reads every store into both surfaces: the classic menu and the
    /// model behind the panel and Settings. Every action ends here.
    private func rebuildMenu() {
        // First, since switching the setting off can show the icons, which
        // the menu and the model then describe.
        syncScreenShareMonitor()
        menuBuilder.rebuild(appMenu)
        model.refresh()
    }

    /// Runs the screen-share poll exactly while its setting is on. Import can
    /// switch the setting on behind the toggle's back, so this follows the
    /// stored value rather than the toggle.
    private func syncScreenShareMonitor() {
        if UserDefaults.standard.hideIconsWhenScreenSharing {
            screenShareMonitor.start()
        } else {
            screenShareMonitor.stop()
            // Switched off mid-share: nothing would ever show the icons this
            // feature hid, so show them now. A manual hide stays.
            if shareHidePolicy.stop(desktopHidden: presentation.isHidden) == .show {
                NSLog("DeskStop: hide while screen sharing switched off — showing icons")
                presentation.show()
                updateStatusIcon()
            }
        }
    }

    // MARK: - Status item interaction

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        guard let button = statusItem.button else { return }
        if isSecondary {
            panel.close()
            showClassicMenu()
        } else {
            panel.toggle(from: button)
        }
    }

    /// Pops the classic menu from the status item without leaving it attached.
    private func showClassicMenu() {
        rebuildMenu()
        statusItem.menu = appMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - App-level menu actions

    /// Toggle presentation mode.
    @objc func toggleHideDesktop() {
        if presentation.isHidden {
            presentation.show()
        } else {
            presentation.hide()
        }
        updateStatusIcon()
        rebuildMenu()
    }

    @objc func setHideDesktopHotkey() {
        let existing = UserDefaults.standard.hideDesktopHotkey
        let chord = HotkeyRecorder.record(
            presetName: "Hide Desktop Icons",
            existing: existing,
            collision: { [weak self] chord in
                guard let self = self,
                      let pidString = self.hotkeyConfig.presetBound(to: chord),
                      let id = UUID(uuidString: pidString),
                      let preset = self.presetStore.find(id: id) else { return nil }
                return preset.name
            })
        guard let chord = chord else { return }   // nil == user cancelled
        UserDefaults.standard.hideDesktopHotkey = chord
        registerAllHotkeys()
        rebuildMenu()
    }

    @objc func removeHideDesktopHotkey() {
        UserDefaults.standard.hideDesktopHotkey = nil
        registerAllHotkeys()
        rebuildMenu()
    }

    @objc func toggleHideOnScreenShare() {
        UserDefaults.standard.hideIconsWhenScreenSharing.toggle()
        rebuildMenu()   // starts or stops the monitor to match
    }

    private func handleShareTick(sharing: Bool) {
        switch shareHidePolicy.tick(sharing: sharing, desktopHidden: presentation.isHidden) {
        case .hide:
            NSLog("DeskStop: screen share detected — hiding icons")
            presentation.hide()
            updateStatusIcon()
            rebuildMenu()
        case .show:
            NSLog("DeskStop: screen share ended — showing icons")
            presentation.show()
            updateStatusIcon()
            rebuildMenu()
        case .none:
            break
        }
    }

    @objc func toggleStartAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Alerts.show(title: "Couldn't change Start at Login",
                        info: error.localizedDescription,
                        style: .warning)
        }
        startAtLoginEnabled = SMAppService.mainApp.status == .enabled
        rebuildMenu()
    }

    @objc func toggleNotifications() {
        UserDefaults.standard.showSuccessNotifications.toggle()
        rebuildMenu()
    }

    @objc func openSettings() {
        showSettings(page: nil)
    }

    /// Opens Settings, on `page` if given, else wherever it was left.
    func showSettings(page: SettingsPage?, layout: UUID? = nil) {
        SettingsWindow.show(model: model, actions: uiActions, page: page, layout: layout)
    }

    @objc func openSchedules() {
        SchedulesWindow.show(scheduleStore: scheduleStore, presetStore: presetStore)
    }

    /// Walkthrough for adding DeskStop as a Focus filter, plus a restore link.
    @objc func showFocusSetup() {
        FocusSetupWindow.show(presetStore: presetStore)
    }

    func renameDisplaySetup(key: String, to name: String?) {
        DisplaySetupNames.setName(name, forKey: key)
        rebuildMenu()
    }

    func moveLayout(_ id: UUID, before target: UUID?, in ids: [UUID], setup: String) {
        LayoutOrder.move(id, before: target, in: ids, forSetup: setup)
        rebuildMenu()
    }

    func moveLayout(_ id: UUID, by offset: Int, in ids: [UUID], setup: String) {
        LayoutOrder.move(id, by: offset, in: ids, forSetup: setup)
        rebuildMenu()
    }

    func setDisplaySetupSymbol(key: String, to symbol: String?) {
        DisplaySetupNames.setSymbol(symbol, forKey: key)
        rebuildMenu()
    }

    @objc func checkForUpdates() {
        updateChecker.checkNow()
    }

    @objc func toggleAutomaticUpdateChecks() {
        UserDefaults.standard.automaticallyCheckForUpdates.toggle()
    }

    @objc func showWelcome() {
        WelcomeTour.show(model: model, actions: uiActions,
                         startPanelTour: { [weak self] in self?.startPanelTour() })
    }

    /// Opens the panel on the Layouts tab with the walk-through's first stop.
    func startPanelTour() {
        guard let button = statusItem.button else { return }
        UserDefaults.standard.set(PanelTab.configurations.rawValue, forKey: "panelSelectedTab")
        model.panelTour = PanelTourStop.allCases.first
        if !panel.isShown { panel.show(from: button) }
    }

    // MARK: - Hidden icons cover

    /// Settings → General: hide icons behind `url`, or behind the wallpaper
    /// when nil (Use Wallpaper). Refuses a file that isn't a readable picture.
    func setHiddenIconsPicture(_ url: URL?) {
        if let url, HiddenIconsCover.thumbnail(at: url, maxPixelSize: 64) == nil {
            Alerts.show(title: "Couldn't use that picture",
                        info: "DeskStop can't read \u{201C}\(url.lastPathComponent)\u{201D} as a picture. Choose another.",
                        style: .warning)
            return
        }
        UserDefaults.standard.hiddenIconsPicture = url
        presentation.rebuildIfHidden()   // icons hidden now get the new cover
        rebuildMenu()
    }

    /// The picture gallery's Choose File: any picture of the user's own.
    func chooseHiddenIconsPictureFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose a Picture"
        panel.message = "Your desktop icons will be hidden behind this picture."
        panel.prompt = "Choose"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setHiddenIconsPicture(url)
    }

    func setAppearance(_ mode: AppearanceMode) {
        UserDefaults.standard.appearanceMode = mode
        AppearanceMode.applyStored()
        rebuildMenu()
    }

    /// Settings → About → Uninstall. Confirms first, offering a backup.
    /// Escape cancels; Return does nothing, so a stray keypress can't
    /// uninstall.
    @objc func uninstall() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Uninstall DeskStop?"
        alert.informativeText = SelfUninstaller.summary
        let uninstallButton = alert.addButton(withTitle: "Uninstall")
        uninstallButton.hasDestructiveAction = true
        uninstallButton.keyEquivalent = ""
        alert.addButton(withTitle: "Export Backup First")
        // NSAlert gives a button titled "Cancel" the Escape key by itself.
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Leave nothing of ours on screen or registered while the files
            // go: hidden icons come back, hotkeys and polling stop.
            if presentation.isHidden { presentation.show() }
            screenShareMonitor.stop()
            hotkeyManager.unregisterAll()
            panel.close()
            NSApp.windows.forEach { $0.orderOut(nil) }
            SelfUninstaller.run()
        case .alertSecondButtonReturn:
            presetActions.exportPresets()
            uninstall()   // back to the question, backup in hand
        default:
            break
        }
    }

    // MARK: - Hotkey wiring

    private func registerAllHotkeys() {
        hotkeyManager.unregisterAll()
        for (presetIDString, chord) in hotkeyConfig.all() {
            guard let id = UUID(uuidString: presetIDString) else { continue }
            let ok = hotkeyManager.register(name: presetIDString,
                                            keyCode: chord.keyCode,
                                            modifiers: carbonToHotkey(chord.modifiers)) { [weak self] in
                self?.presetActions.restorePresetByID(id)
            }
            if !ok {
                NSLog("DeskStop: failed to register hotkey for preset \(presetIDString) — chord may be taken")
            }
        }
        if let chord = UserDefaults.standard.hideDesktopHotkey {
            let ok = hotkeyManager.register(name: "__hideDesktop__",
                                            keyCode: chord.keyCode,
                                            modifiers: carbonToHotkey(chord.modifiers)) { [weak self] in
                self?.toggleHideDesktop()
            }
            if !ok {
                NSLog("DeskStop: failed to register hide-desktop hotkey — chord may be taken")
            }
        }
        if let chord = UserDefaults.standard.cyclePresetsHotkey {
            let ok = hotkeyManager.register(name: "__cyclePresets__",
                                            keyCode: chord.keyCode,
                                            modifiers: carbonToHotkey(chord.modifiers)) { [weak self] in
                self?.presetActions.cyclePresets()
            }
            if !ok {
                NSLog("DeskStop: failed to register cycle-presets hotkey — chord may be taken")
            }
        }
    }

    @objc func setCyclePresetsHotkey() {
        let chord = HotkeyRecorder.record(
            presetName: "Restore Next Layout",
            existing: UserDefaults.standard.cyclePresetsHotkey,
            collision: { [weak self] chord in
                guard let self = self,
                      let pidString = self.hotkeyConfig.presetBound(to: chord),
                      let id = UUID(uuidString: pidString),
                      let preset = self.presetStore.find(id: id) else { return nil }
                return preset.name
            })
        guard let chord = chord else { return }
        UserDefaults.standard.cyclePresetsHotkey = chord
        registerAllHotkeys()
        rebuildMenu()
    }

    @objc func removeCyclePresetsHotkey() {
        UserDefaults.standard.cyclePresetsHotkey = nil
        registerAllHotkeys()
        rebuildMenu()
    }

    private func carbonToHotkey(_ raw: UInt32) -> HotkeyModifiers {
        var m: HotkeyModifiers = []
        if raw & UInt32(cmdKey)     != 0 { m.insert(.command) }
        if raw & UInt32(optionKey)  != 0 { m.insert(.option) }
        if raw & UInt32(controlKey) != 0 { m.insert(.control) }
        if raw & UInt32(shiftKey)   != 0 { m.insert(.shift) }
        return m
    }

    // MARK: - Helpers

    private func notifySuccess(title: String, body: String, undoable: Bool = false) {
        if UserDefaults.standard.showSuccessNotifications {
            Notifier.shared.notify(title: title, body: body, undoable: undoable)
        } else {
            NSLog("DeskStop (silent) \(title) — \(body)")
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
