import Foundation
import SchedulingCore

/// A full backup of the app's configuration — presets, hotkeys, schedules,
/// per-display default presets, and the main toggles — as one versioned file.
/// Import preserves preset UUIDs so hotkey/schedule/default references stay
/// valid, and merges into the existing setup rather than wiping it.
struct ConfigBundle: Codable {
    /// Bump when the shape changes incompatibly; decode tolerates unknown
    /// higher versions by best-effort (all fields optional below).
    var version: Int = 1
    var presets: [Preset] = []
    /// Preset-UUID-string → chord.
    var hotkeys: [String: HotkeyChord] = [:]
    var schedules: [Schedule] = []
    /// Category-key → default preset UUID string.
    var defaults: [String: String] = [:]
    var settings: Settings = Settings()

    struct Settings: Codable {
        var showSuccessNotifications: Bool?
        var hideIconsWhenScreenSharing: Bool?
        var hideDesktopHotkey: HotkeyChord?
        var cyclePresetsHotkey: HotkeyChord?
        /// "system", "light" or "dark". Absent leaves the current choice alone.
        var appearanceMode: String?
        /// "wallpaper" or "picture", and the picture's path. A path missing on
        /// the Mac imported to falls back to the wallpaper, and Settings says so.
        var hiddenIconsCover: String?
        var hiddenIconsPicture: String?
        /// Display-setup key → the user's name and icon for it.
        var displaySetupNames: [String: String]?
        var displaySetupSymbols: [String: String]?
    }
}

/// Reads and writes `ConfigBundle`s against the live stores. Export gathers;
/// import merges (preset IDs preserved, so cross-references survive).
struct ConfigBundleService {
    let presetStore: PresetStore
    let hotkeyConfig: HotkeyConfigStore
    let scheduleStore: ScheduleStore
    let defaults: DefaultPresetStore

    func export() -> ConfigBundle {
        var settings = ConfigBundle.Settings()
        settings.showSuccessNotifications = UserDefaults.standard.showSuccessNotifications
        settings.hideIconsWhenScreenSharing = UserDefaults.standard.hideIconsWhenScreenSharing
        settings.hideDesktopHotkey = UserDefaults.standard.hideDesktopHotkey
        settings.cyclePresetsHotkey = UserDefaults.standard.cyclePresetsHotkey
        settings.appearanceMode = UserDefaults.standard.appearanceMode.rawValue
        let picture = UserDefaults.standard.hiddenIconsPicture
        settings.hiddenIconsCover = picture == nil ? "wallpaper" : "picture"
        settings.hiddenIconsPicture = picture?.path
        settings.displaySetupNames = DisplaySetupNames.all()
        settings.displaySetupSymbols = DisplaySetupNames.allSymbols()
        return ConfigBundle(
            presets: presetStore.list(),
            hotkeys: hotkeyConfig.all(),
            schedules: scheduleStore.load(),
            defaults: defaults.exportMap(),
            settings: settings)
    }

    struct ImportSummary { let presets: Int; let hotkeys: Int; let schedules: Int; let setupNames: Int }

    /// Merge a bundle into the live stores. Presets are written under their
    /// original IDs (overwriting a same-ID preset), so hotkeys, schedules, and
    /// defaults that reference those IDs keep working.
    @discardableResult
    func merge(_ bundle: ConfigBundle) -> ImportSummary {
        for preset in bundle.presets { try? presetStore.save(preset) }
        hotkeyConfig.merge(bundle.hotkeys)

        var schedules = scheduleStore.load()
        for incoming in bundle.schedules {
            if let i = schedules.firstIndex(where: { $0.id == incoming.id }) {
                schedules[i] = incoming
            } else {
                schedules.append(incoming)
            }
        }
        scheduleStore.saveAll(schedules)

        defaults.merge(bundle.defaults)

        let s = bundle.settings
        if let v = s.showSuccessNotifications { UserDefaults.standard.showSuccessNotifications = v }
        if let v = s.hideIconsWhenScreenSharing { UserDefaults.standard.hideIconsWhenScreenSharing = v }
        if let v = s.hideDesktopHotkey { UserDefaults.standard.hideDesktopHotkey = v }
        if let v = s.cyclePresetsHotkey { UserDefaults.standard.cyclePresetsHotkey = v }
        switch s.hiddenIconsCover {
        case "wallpaper": UserDefaults.standard.hiddenIconsPicture = nil
        case "picture": if let v = s.hiddenIconsPicture {
            UserDefaults.standard.hiddenIconsPicture = URL(fileURLWithPath: v)
        }
        default: break
        }
        for (key, name) in s.displaySetupNames ?? [:] { DisplaySetupNames.setName(name, forKey: key) }
        for (key, symbol) in s.displaySetupSymbols ?? [:] { DisplaySetupNames.setSymbol(symbol, forKey: key) }
        if let v = s.appearanceMode.flatMap(AppearanceMode.init(rawValue:)) {
            UserDefaults.standard.appearanceMode = v
            AppearanceMode.applyStored()
        }

        return ImportSummary(presets: bundle.presets.count,
                             hotkeys: bundle.hotkeys.count,
                             schedules: bundle.schedules.count,
                             setupNames: s.displaySetupNames?.count ?? 0)
    }
}
