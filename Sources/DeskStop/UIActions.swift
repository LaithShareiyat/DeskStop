import AppKit
import SwiftUI

/// Everything the menu bar panel and Settings can ask for. Each call lands on
/// the same `AppDelegate` or `PresetActionsController` method the classic
/// menu uses, so no behaviour lives in the SwiftUI layer.
///
/// Built with nil targets it does nothing at all, which is what the debug UI
/// renderer and SwiftUI's environment default rely on.
final class UIActions {
    private weak var app: AppDelegate?
    private weak var presets: PresetActionsController?
    /// Closes the menu bar panel, if it is open.
    var closePanel: () -> Void = {}
    /// Re-reads the stores into the model.
    var refresh: () -> Void = {}

    init(app: AppDelegate?, presets: PresetActionsController?) {
        self.app = app
        self.presets = presets
    }

    /// For anything that can show a modal — an alert, the shortcut recorder,
    /// the app picker, a save or open panel — or that moves icons. The panel
    /// closes first and the work runs on the next turn of the run loop, so no
    /// modal ever runs under a popover that is still on screen.
    private func afterClosingPanel(_ work: @escaping () -> Void) {
        closePanel()
        DispatchQueue.main.async(execute: work)
    }

    /// For a change made in place, with the panel left open. Refreshes even
    /// when the action refused (a login item macOS would not register), so
    /// the switch that asked snaps back.
    private func inPlace(_ work: () -> Void) {
        work()
        refresh()
    }

    // MARK: - Configurations

    func newConfiguration() { afterClosingPanel { [weak presets] in presets?.newPreset() } }
    func restore(_ id: UUID) { afterClosingPanel { [weak presets] in presets?.restorePresetByID(id) } }
    func undoLastRestore() { afterClosingPanel { [weak presets] in presets?.undoLastRestore() } }
    func cycleConfigurations() { afterClosingPanel { [weak presets] in presets?.cyclePresets() } }
    func updateFromDesktop(_ id: UUID) {
        afterClosingPanel { [weak presets] in presets?.saveCurrentArrangement(id: id) }
    }
    func captureApps(_ id: UUID) { afterClosingPanel { [weak presets] in presets?.captureOpenApps(id: id) } }
    func setShortcut(_ id: UUID) { afterClosingPanel { [weak presets] in presets?.setHotkey(id: id) } }
    func rename(_ id: UUID) { afterClosingPanel { [weak presets] in presets?.renamePreset(id: id) } }
    /// Settings' name field. Refreshes even when refused, so the field
    /// shows the name that was kept.
    func rename(_ id: UUID, to name: String) { inPlace { presets?.renamePreset(id: id, to: name) } }
    func editInSettings(_ id: UUID) { openSettings(page: .layouts, layout: id) }
    /// `then` gets the copy's id, for Settings to select it.
    func duplicate(_ id: UUID, then: @escaping (UUID) -> Void = { _ in }) {
        inPlace {
            if let copy = presets?.duplicatePreset(id: id) { then(copy) }
        }
    }
    func delete(_ id: UUID) { afterClosingPanel { [weak presets] in presets?.deletePreset(id: id) } }

    func clearApps(_ id: UUID) { inPlace { presets?.clearSavedApps(id: id) } }
    func removeShortcut(_ id: UUID) { inPlace { presets?.removeHotkey(id: id) } }
    func toggleDefault(_ id: UUID) { inPlace { presets?.toggleDefaultPreset(id: id) } }
    func toggleRestoreIcons(_ id: UUID) { inPlace { presets?.toggleRestoreIconPositions(id: id) } }
    func toggleRestoreDisplays(_ id: UUID) { inPlace { presets?.toggleRestoreDisplayArrangement(id: id) } }
    func toggleRestoreModes(_ id: UUID) { inPlace { presets?.toggleRestoreDisplayModes(id: id) } }
    func toggleLaunchApps(_ id: UUID) { inPlace { presets?.toggleLaunchAppsOnRestore(id: id) } }

    /// Nil or empty goes back to the name macOS reports.
    func renameDisplaySetup(_ key: String, to name: String?) {
        inPlace { app?.renameDisplaySetup(key: key, to: name) }
    }

    /// Reorders a layout within its display setup's list; `ids` is that list
    /// in its current order.
    func moveLayout(_ id: UUID, before target: UUID?, in ids: [UUID], setup: String) {
        inPlace { app?.moveLayout(id, before: target, in: ids, setup: setup) }
    }

    func moveLayout(_ id: UUID, by offset: Int, in ids: [UUID], setup: String) {
        inPlace { app?.moveLayout(id, by: offset, in: ids, setup: setup) }
    }

    /// Nil goes back to the default icon.
    func setDisplaySetupSymbol(_ key: String, to symbol: String?) {
        inPlace { app?.setDisplaySetupSymbol(key: key, to: symbol) }
    }

    // MARK: - App-level switches

    func toggleHideDesktop() { inPlace { app?.toggleHideDesktop() } }
    func toggleHideOnScreenShare() { inPlace { app?.toggleHideOnScreenShare() } }
    func toggleNotifications() { inPlace { app?.toggleNotifications() } }
    func toggleStartAtLogin() { inPlace { app?.toggleStartAtLogin() } }

    // MARK: - Shortcuts (the recorder is modal)

    func recordHideShortcut() { afterClosingPanel { [weak app] in app?.setHideDesktopHotkey() } }
    func clearHideShortcut() { inPlace { app?.removeHideDesktopHotkey() } }
    func recordCycleShortcut() { afterClosingPanel { [weak app] in app?.setCyclePresetsHotkey() } }
    func clearCycleShortcut() { inPlace { app?.removeCyclePresetsHotkey() } }

    // MARK: - Windows and files

    func openSettings(page: SettingsPage? = nil, layout: UUID? = nil) {
        afterClosingPanel { [weak app] in app?.showSettings(page: page, layout: layout) }
    }
    func openSchedules() { afterClosingPanel { [weak app] in app?.openSchedules() } }
    func openFocusSetup() { afterClosingPanel { [weak app] in app?.showFocusSetup() } }
    func openWelcome() { afterClosingPanel { [weak app] in app?.showWelcome() } }
    func exportSettings() { afterClosingPanel { [weak presets] in presets?.exportPresets() } }
    func importSettings() { afterClosingPanel { [weak presets] in presets?.importPresets() } }
    func openNotificationSettings() { Permissions.openNotificationSettings() }
    /// Makes macOS show DeskStop's banners: asks for permission while it
    /// can, otherwise opens Notifications in System Settings with the guide
    /// card (which also covers setting the alert style to Banners).
    func turnOnNotifications(alertStyleOnly: Bool) {
        afterClosingPanel {
            if alertStyleOnly {
                PermissionCenter.shared.guide(.notifications)
            } else {
                PermissionCenter.shared.request(.notifications)
            }
        }
    }
    func quit() { NSApp.terminate(nil) }

    // MARK: - Feedback

    func reportBug() { if let url = Feedback.bugReportURL { NSWorkspace.shared.open(url) } }
    func requestFeature() { if let url = Feedback.featureRequestURL { NSWorkspace.shared.open(url) } }
    func copySystemDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Feedback.systemDetails, forType: .string)
    }

    // MARK: - Appearance, permissions, uninstall

    func setAppearance(_ mode: AppearanceMode) { inPlace { app?.setAppearance(mode) } }
    func openDonations() { if let url = Donations.url { NSWorkspace.shared.open(url) } }
    /// nil goes back to the wallpaper.
    func setHiddenIconsPicture(_ url: URL?) { inPlace { app?.setHiddenIconsPicture(url) } }
    func chooseHiddenIconsPictureFile() { afterClosingPanel { [weak app] in app?.chooseHiddenIconsPictureFile() } }

    /// System prompts and System Settings both pull focus, so the panel closes.
    func turnOn(_ permission: PermissionKind) {
        afterClosingPanel { PermissionCenter.shared.request(permission) }
    }
    func startOver(_ permission: PermissionKind) {
        afterClosingPanel { PermissionCenter.shared.startOver(permission) }
    }
    func uninstall() { afterClosingPanel { [weak app] in app?.uninstall() } }

    // MARK: - Updates

    /// Can show an alert, so the panel closes first.
    func checkForUpdates() { afterClosingPanel { [weak app] in app?.checkForUpdates() } }
    func toggleAutomaticUpdateChecks() { inPlace { app?.toggleAutomaticUpdateChecks() } }
}

private struct UIActionsKey: EnvironmentKey {
    static let defaultValue = UIActions(app: nil, presets: nil)
}

extension EnvironmentValues {
    var uiActions: UIActions {
        get { self[UIActionsKey.self] }
        set { self[UIActionsKey.self] = newValue }
    }
}

extension AppModel {
    /// A switch bound to a toggling action. The existing actions *toggle*
    /// rather than set, so the action runs only when the new value differs
    /// from what the model says is true now.
    func toggleBinding(_ keyPath: KeyPath<PanelSnapshot, Bool>,
                       _ toggle: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { self.snapshot[keyPath: keyPath] },
                set: { newValue in
                    if newValue != self.snapshot[keyPath: keyPath] { toggle() }
                })
    }
}
