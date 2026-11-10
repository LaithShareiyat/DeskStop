import Foundation
import DisplayCore

/// An app remembered with a preset, launched on restore if not already running.
struct SavedApp: Codable, Equatable {
    var bundleIdentifier: String
    var name: String
}

/// One saved desktop arrangement, scoped to a single display configuration.
/// Identity is by UUID so two presets can share a name (one per category).
struct Preset: Codable, Identifiable {
    var id: UUID
    var name: String
    /// Stable display-configuration fingerprint (`DisplayConfiguration.key`).
    /// Presets with the same `categoryKey` share a display setup.
    var categoryKey: String
    /// Human-readable category name, e.g. "Built-in Retina Display + DELL U2719D".
    /// Persisted so it reads even if a display isn't attached.
    var categoryLabel: String
    var positions: [IconPosition]
    /// Opt-in to put the icons back on restore. Unlike the other flags,
    /// **absent means ON** (see `RestoreFlags`).
    var restoreIconPositions: Bool?
    /// Apps to launch on restore; nil for icon-only presets.
    var apps: [SavedApp]?
    /// Opt-in to launch `apps` on restore, however it is triggered. nil means off.
    var launchAppsOnRestore: Bool?
    /// Display layout captured when this preset was saved; nil if none.
    var displayArrangement: DisplayArrangement?
    /// Opt-in to put the displays back into `displayArrangement` on restore.
    /// nil means off.
    var restoreDisplayArrangement: Bool?
    /// Opt-in to set each display back to the resolution, scaling and refresh
    /// rate in `displayArrangement`. nil means off.
    var restoreDisplayModes: Bool?

    /// Effective flag: move icons unless explicitly disabled, and only when
    /// positions were actually captured.
    var restoresIconPositions: Bool {
        RestoreFlags.restoresIconPositions(stored: restoreIconPositions,
                                           hasPositions: !positions.isEmpty)
    }

    /// Effective flag: launch on restore only when explicitly enabled and
    /// there are apps to launch.
    var launchesAppsOnRestore: Bool {
        RestoreFlags.launchesApps(stored: launchAppsOnRestore,
                                  hasApps: !(apps ?? []).isEmpty)
    }

    /// Effective flag: rearrange displays only when explicitly enabled and an
    /// arrangement was actually captured.
    var restoresDisplayArrangement: Bool {
        RestoreFlags.restoresDisplayArrangement(stored: restoreDisplayArrangement,
                                                hasArrangement: displayArrangement != nil)
    }

    /// Effective flag: set display modes only when explicitly enabled and modes
    /// were captured.
    var restoresDisplayModes: Bool {
        RestoreFlags.restoresDisplayModes(stored: restoreDisplayModes,
                                          hasModes: displayArrangement?.hasModes ?? false)
    }

    /// A restore touches the displays at all: moves them, sets their modes, or both.
    var changesDisplays: Bool { restoresDisplayArrangement || restoresDisplayModes }

    /// What a restore does, whichever way it was started: menu, hotkey, URL,
    /// auto-restore, schedule, Shortcuts action or Focus filter.
    var restorePlan: RestorePlan {
        RestorePlan(writesIcons: restoresIconPositions,
                    movesDisplays: changesDisplays,
                    launchesApps: (launchAppsOnRestore ?? false) && !(apps ?? []).isEmpty)
    }

    init(id: UUID = UUID(),
         name: String,
         categoryKey: String,
         categoryLabel: String,
         positions: [IconPosition],
         restoreIconPositions: Bool? = nil,
         apps: [SavedApp]? = nil,
         launchAppsOnRestore: Bool? = nil,
         displayArrangement: DisplayArrangement? = nil,
         restoreDisplayArrangement: Bool? = nil,
         restoreDisplayModes: Bool? = nil) {
        self.id = id
        self.name = name
        self.categoryKey = categoryKey
        self.categoryLabel = categoryLabel
        self.positions = positions
        self.restoreIconPositions = restoreIconPositions
        self.apps = apps
        self.launchAppsOnRestore = launchAppsOnRestore
        self.displayArrangement = displayArrangement
        self.restoreDisplayArrangement = restoreDisplayArrangement
        self.restoreDisplayModes = restoreDisplayModes
    }
}
