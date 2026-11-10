import AppKit
import Combine
import SchedulingCore

/// One desktop configuration as the panel lists it.
struct ConfigurationSummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isDefault: Bool
    let shortcut: String?
    let iconCount: Int
    let displayCount: Int
    let mainDisplayName: String?
    let appNames: [String]
    /// Each display's saved resolution, main display first, e.g.
    /// "LG HDR 4K at 2560 × 1440, 60 Hz". Empty if none was saved.
    let displayModes: [String]
    /// Effective flags — what a restore will actually do (`RestoreFlags`).
    let restoresIcons: Bool
    let restoresDisplays: Bool
    let restoresDisplayModes: Bool
    let launchesApps: Bool

    var hasPositions: Bool { iconCount > 0 }
    var hasArrangement: Bool { displayCount > 0 }
    var hasModes: Bool { !displayModes.isEmpty }
    var hasApps: Bool { !appNames.isEmpty }
    var restoresNothing: Bool {
        !restoresIcons && !restoresDisplays && !restoresDisplayModes && !launchesApps
    }

    /// "24 icons · 2 displays · 3 apps", naming only what a restore does.
    var restoreSummary: String {
        var parts: [String] = []
        if restoresIcons { parts.append(Self.count(iconCount, "icon")) }
        if restoresDisplays || restoresDisplayModes { parts.append(Self.count(displayCount, "display")) }
        if launchesApps { parts.append(Self.count(appNames.count, "app")) }
        return restoresNothing ? "No restore options on" : parts.joined(separator: " · ")
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}

/// A display setup Settings lets the user name: the one in use now, plus
/// every setup that has layouts saved for it.
struct DisplaySetupSummary: Identifiable, Equatable {
    /// `DisplayConfiguration.key`.
    let id: String
    /// The name built from the display names macOS reports.
    let detectedName: String
    /// The user's name for it, if they gave one.
    let customName: String?
    let layoutCount: Int
    let isCurrent: Bool
    /// The icon drawn for it: the user's choice, or the default.
    let symbol: String
    /// Whether `symbol` is the user's choice rather than the default.
    let hasCustomSymbol: Bool
}

/// The configurations saved for one display setup.
struct DisplayGroup: Identifiable, Equatable {
    /// The display setup's `DisplayConfiguration.key`.
    let id: String
    let label: String
    let configurations: [ConfigurationSummary]
    var symbol = "display"
}

/// Everything the menu bar panel and the Settings window show, as plain
/// values. Views never read a store: they read this, and ask `UIActions`
/// to change things.
struct PanelSnapshot: Equatable {
    var currentDisplayLabel = ""
    var currentDisplaySymbol = "laptopcomputer"
    var isDocked = false
    /// The configurations for the display setup in use now. Always present,
    /// possibly empty.
    var currentGroup = DisplayGroup(id: "", label: "", configurations: [])
    var otherGroups: [DisplayGroup] = []
    var undoTitle: String?
    var nextSchedule: String?
    var scheduleCount = 0
    var hideOnScreenShare = false
    var showNotifications = true
    var startAtLogin = false
    var desktopHidden = false
    var hideShortcut: String?
    var cycleShortcut: String?
    var displaySetups: [DisplaySetupSummary] = []
    var automaticallyCheckForUpdates = true
    /// "1.2.0", or "development build" when run without a bundle.
    var appVersion = ""
    var appearanceMode: AppearanceMode = .system
    /// The picture hidden icons sit behind; nil for the wallpaper.
    var hiddenIconsPicture: URL?
    /// Chosen, but since moved or deleted, so the wallpaper is used.
    var hiddenIconsPictureMissing = false

    var defaultConfigurationName: String? {
        currentGroup.configurations.first(where: \.isDefault)?.name
    }

}

final class AppModel: ObservableObject {
    @Published private(set) var snapshot: PanelSnapshot
    /// Set while Settings is open: macOS will not put notifications on
    /// screen, a state the Show Notifications switch cannot detect or fix.
    @Published var notificationWarning: String?
    /// True when the warning is about the alert style (macOS allows the
    /// notifications but shows no banner), false when macOS hasn't allowed
    /// them at all. Decides what Turn On does.
    @Published var notificationsHiddenByAlertStyle = false
    /// Visible height of the screen the status item is on, set each time the
    /// panel opens. Not part of the snapshot: it describes where the panel is
    /// shown, not what the stores hold.
    @Published var panelScreenHeight: CGFloat?
    /// The panel walk-through's current stop, or nil when it isn't running.
    @Published var panelTour: PanelTourStop?

    private let source: () -> PanelSnapshot

    init(source: @escaping () -> PanelSnapshot) {
        self.source = source
        self.snapshot = source()
    }

    /// Re-reads every store. Always publishes, even when nothing changed: a
    /// switch the user flipped but the app refused (a login item macOS would
    /// not register) has to be told to snap back.
    func refresh() {
        snapshot = source()
    }

    /// Asks macOS whether it will actually show a banner. Only while Settings
    /// is open: it is an XPC round trip.
    func refreshNotificationWarning() {
        Notifier.shared.deliveryStatus { [weak self] status in
            switch status {
            case .willShow:
                self?.notificationWarning = nil
                self?.notificationsHiddenByAlertStyle = false
            case .notAuthorized:
                self?.notificationWarning = "macOS isn't allowing DeskStop's notifications yet."
                self?.notificationsHiddenByAlertStyle = false
            case .bannersDisabled:
                self?.notificationWarning = "macOS is set to show no banner for them."
                self?.notificationsHiddenByAlertStyle = true
            }
        }
    }
}

/// Reads the live stores into a `PanelSnapshot`. The same reads `MenuBuilder`
/// makes for the classic menu, so the two never disagree.
struct PanelSnapshotSource {
    let presetStore: PresetStore
    let hotkeyConfig: HotkeyConfigStore
    let defaults: DefaultPresetStore
    let displayMonitor: DisplayMonitor
    let scheduler: Scheduler
    let scheduleStore: ScheduleStore
    let undoStore: UndoSlotStore
    let isDesktopHidden: () -> Bool
    /// Cached by AppDelegate: `SMAppService.status` is a blocking XPC call.
    let isStartAtLoginEnabled: () -> Bool

    private static let hintFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()

    func make() -> PanelSnapshot {
        let config = displayMonitor.currentConfiguration
        let groups = presetStore.presetsByCategory()
        let current = groups.first { $0.key == config.key }
        let userDefaults = UserDefaults.standard

        var s = PanelSnapshot()
        s.currentDisplayLabel = config.displayName
        s.currentDisplaySymbol = config.displaySymbol
        s.isDocked = config.displayUUIDs.count > 1
        s.currentGroup = DisplayGroup(id: config.key, label: config.displayName,
                                      configurations: (current?.presets ?? []).map(summary),
                                      symbol: config.displaySymbol)
        s.otherGroups = groups
            .filter { $0.key != config.key }
            .map { DisplayGroup(id: $0.key, label: $0.label, configurations: $0.presets.map(summary),
                                symbol: DisplaySetupNames.resolvedSymbol(forKey: $0.key)) }
        // Offered only while the display setup the snapshot was taken on is
        // still active — undoing onto different screens would misplace icons.
        if let snap = undoStore.load(), snap.categoryKey == config.key {
            s.undoTitle = "Undo Last Restore"
        }
        if let upcoming = scheduler.nextUpcoming() {
            s.nextSchedule = "Next: \(upcoming.schedule.name) at \(Self.hintFormatter.string(from: upcoming.date))"
        }
        s.scheduleCount = scheduleStore.load().count
        s.hideOnScreenShare = userDefaults.hideIconsWhenScreenSharing
        s.showNotifications = userDefaults.showSuccessNotifications
        s.startAtLogin = isStartAtLoginEnabled()
        s.desktopHidden = isDesktopHidden()
        s.hideShortcut = userDefaults.hideDesktopHotkey.map(HotkeyFormatter.display)
        s.cycleShortcut = userDefaults.cyclePresetsHotkey.map(HotkeyFormatter.display)
        s.appearanceMode = userDefaults.appearanceMode
        s.hiddenIconsPicture = userDefaults.hiddenIconsPicture
        s.hiddenIconsPictureMissing = s.hiddenIconsPicture != nil && userDefaults.hiddenIconsPictureInUse == nil
        s.displaySetups = displaySetups(current: config)
        s.automaticallyCheckForUpdates = userDefaults.automaticallyCheckForUpdates
        s.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "development build"
        return s
    }

    /// The current setup first, then the others by name. Detected names come
    /// from the layout files; a custom name never overwrites them.
    private func displaySetups(current: DisplayConfiguration) -> [DisplaySetupSummary] {
        var detected: [String: String] = [:]
        var counts: [String: Int] = [:]
        for preset in presetStore.list() {
            detected[preset.categoryKey] = detected[preset.categoryKey] ?? preset.categoryLabel
            counts[preset.categoryKey, default: 0] += 1
        }
        detected[current.key] = current.label
        let names = DisplaySetupNames.all()
        return detected
            .map { key, name in
                DisplaySetupSummary(id: key, detectedName: name, customName: names[key],
                                    layoutCount: counts[key] ?? 0, isCurrent: key == current.key,
                                    symbol: DisplaySetupNames.resolvedSymbol(forKey: key),
                                    hasCustomSymbol: DisplaySetupNames.symbol(forKey: key) != nil)
            }
            .sorted {
                if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
                return ($0.customName ?? $0.detectedName)
                    .localizedCaseInsensitiveCompare($1.customName ?? $1.detectedName) == .orderedAscending
            }
    }

    private func summary(_ preset: Preset) -> ConfigurationSummary {
        let arrangement = preset.displayArrangement
        let mainName = arrangement?.mainDisplayUUID.flatMap { uuid in
            arrangement?.placements.first(where: { $0.uuid == uuid })?.name
        }
        let main = arrangement?.mainDisplayUUID
        let modes = (arrangement?.placements ?? [])
            .sorted { $0.uuid == main && $1.uuid != main }
            .compactMap { p in p.mode.map { "\(p.name ?? "Display") at \($0.summary)" } }
        return ConfigurationSummary(
            id: preset.id,
            name: preset.name,
            isDefault: defaults.isDefault(presetID: preset.id, forCategory: preset.categoryKey),
            shortcut: hotkeyConfig.chord(forPresetID: preset.id).map(HotkeyFormatter.display),
            iconCount: preset.positions.count,
            displayCount: arrangement?.placements.count ?? 0,
            mainDisplayName: mainName,
            appNames: (preset.apps ?? []).map(\.name),
            displayModes: modes,
            restoresIcons: preset.restoresIconPositions,
            restoresDisplays: preset.restoresDisplayArrangement,
            restoresDisplayModes: preset.restoresDisplayModes,
            launchesApps: preset.launchesAppsOnRestore)
    }
}
