import Foundation
import DisplayCore

#if canImport(AppIntents)
import AppIntents

// MARK: - App Intents
//
// Restore and Save as App Intents, for Shortcuts (including personal
// automations), Spotlight and Siri.
//
// Shortcuts and Spotlight find them through the App Intents metadata bundle
// (`Contents/Resources/Metadata.appintents`). `swift build` never writes it;
// Scripts/build-app.sh builds with Xcode and runs the metadata processor.

enum DesktopPresetIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case presetNotFound
    case emptyArrangement(name: String)
    case finderNotEditable(reason: String)
    case wrongDisplaySetup(presetLabel: String, currentLabel: String)
    case restoreInProgress

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .presetNotFound:
            return "That layout no longer exists."
        case .emptyArrangement(let name):
            return "\u{201C}\(name)\u{201D} has no restore options turned on."
        case .finderNotEditable(let reason):
            return "Can't move desktop icons right now. \(reason)"
        case .wrongDisplaySetup(let presetLabel, let currentLabel):
            return "That layout is for \(presetLabel), but you're on \(currentLabel). Use the menu bar app to save it for these displays."
        case .restoreInProgress:
            return "A restore is already in progress. Try again in a moment."
        }
    }
}

// MARK: - Entity

/// A saved desktop arrangement, surfaced to the system as a pickable noun.
/// Backed by the same on-disk presets the menu bar app reads.
struct PresetEntity: AppEntity, Identifiable {
    let id: UUID
    let name: String
    let categoryLabel: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Layout")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(categoryLabel)")
    }

    static var defaultQuery = PresetEntityQuery()

    init(id: UUID, name: String, categoryLabel: String) {
        self.id = id
        self.name = name
        self.categoryLabel = categoryLabel
    }

    init(_ preset: Preset) {
        self.init(id: preset.id, name: preset.name, categoryLabel: preset.displaySetupName)
    }
}

/// Lets the system resolve presets by id and list them in the Shortcuts picker.
struct PresetEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PresetEntity] {
        let store = PresetStore()
        return identifiers.compactMap { store.find(id: $0).map(PresetEntity.init) }
    }

    func suggestedEntities() async throws -> [PresetEntity] {
        PresetStore().list().map(PresetEntity.init)
    }
}

// MARK: - Restore

struct RestorePresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Restore Layout"
    static var description = IntentDescription(
        "Puts your desktop back the way a saved layout has it, and opens its saved apps if that is turned on for the layout."
    )
    // No window needed — this runs entirely against Finder.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Layout")
    var preset: PresetEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await LayoutRestorer.restore(id: preset.id)
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: message)))
    }
}

/// The restore both the Restore Layout action and the Focus filter run, the
/// same as the menu: icons, displays, and the saved apps if the layout opens
/// them. Returns what to say.
enum LayoutRestorer {
    @MainActor
    static func restore(id: UUID) async throws -> String {
        guard let stored = PresetStore().find(id: id) else {
            throw DesktopPresetIntentError.presetNotFound
        }
        let plan = stored.restorePlan
        guard !plan.isEmpty else {
            throw DesktopPresetIntentError.emptyArrangement(name: stored.name)
        }
        let current = DisplayConfiguration.current()
        if plan.requiresMatchingDisplays, stored.categoryKey != current.key {
            throw DesktopPresetIntentError.wrongDisplaySetup(presetLabel: stored.displaySetupName,
                                                             currentLabel: current.displayName)
        }
        // Peek before launching apps, so a rejected restore opens nothing.
        guard !DisplayArrangementApplier.isBusy else {
            throw DesktopPresetIntentError.restoreInProgress
        }
        if plan.launchesApps {
            RunningApps.launch(stored.apps ?? [])
        }
        // Same guard the menu path uses — never fight Finder's Sort By / Stacks,
        // which only matters when this restore writes icons.
        if plan.requiresEditableFinder {
            let settings = FinderSettings.read()
            guard settings.positionsAreEditable else {
                let reason: String
                if settings.groupBy != "None" {
                    reason = "Stacks are on. Right-click the desktop, turn off Use Stacks, then try again."
                } else {
                    reason = "The desktop is sorted by \u{201C}\(settings.arrangeBy)\u{201D}. Right-click the desktop, choose Sort By › None, then try again."
                }
                throw DesktopPresetIntentError.finderNotEditable(reason: reason)
            }
        }

        // A distinct, transient condition (another restore or undo is in flight; see
        // DisplayArrangementApplier.reserve), not a data problem.
        guard DisplayArrangementApplier.reserve() else {
            throw DesktopPresetIntentError.restoreInProgress
        }

        UndoSlotStore().stashCurrentArrangement(displacedBy: stored.name,
                                                categoryKey: DisplayConfiguration.current().key,
                                                displayArrangement: DisplayArrangementApplier.undoArrangement(for: stored))
        // This intent builds its own stores, so it can't reach the live
        // DisplayMonitor and suppression is inert here. That's accepted: a re-origin
        // doesn't change which displays are attached, so the key-changed guard and
        // the policy's alreadyCorrect check stop any echo.
        let applier = DisplayArrangementApplier(displayMonitor: DisplayMonitor())
        let outcome: ArrangementOutcome = await withCheckedContinuation { continuation in
            applier.applyThenSettle(for: stored) { continuation.resume(returning: $0) }
        }
        var arrangementNote = ""
        switch outcome {
        case .skipped(let reason):
            arrangementNote = " \(reason)"
        case .partlyApplied(let note):
            arrangementNote = " \(note)"
        case .rolledBack(let underlying):
            arrangementNote = " Displays were put back as they were. \(underlying)"
        case .rollbackFailed(let underlying):
            arrangementNote = " Displays may not be as you expect. Check System Settings › Displays. \(underlying)"
        case .applied, .alreadyCorrect, .notRequested:
            break
        }
        guard plan.writesIcons else {
            return "Restored \u{201C}\(stored.name)\u{201D}. \(plan.nonIconSummary ?? "")\(arrangementNote)"
        }
        let result = try IconArrangement.restore(positions: stored.positions)
        NSLog("DeskStop AppIntent restore '\(stored.name)': \(result.succeeded)/\(result.attempted)")
        let notes = result.notes.map { " " + $0 }.joined()
        if !result.hasProblems {
            return "Restored \u{201C}\(stored.name)\u{201D}.\(notes)\(arrangementNote)"
        } else {
            return "\(result.problemTitle ?? "Couldn't restore every icon"). Restored \(result.succeeded) of \(result.attempted) icons from \u{201C}\(stored.name)\u{201D}.\(notes)\(arrangementNote)"
        }
    }
}

/// Restores a layout when a Focus turns on: System Settings → Focus → the
/// Focus → Focus Filters → Add Filter → DeskStop. When the Focus turns off the
/// system runs the filter with no layout, which does nothing.
struct RestoreLayoutFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Restore Layout"
    static var description: IntentDescription? = IntentDescription(
        "Puts your desktop back the way a saved layout has it when this Focus turns on."
    )

    @Parameter(title: "Layout")
    var preset: PresetEntity?

    var displayRepresentation: DisplayRepresentation {
        if let preset {
            return DisplayRepresentation(title: "Restore \(preset.name)", subtitle: "\(preset.categoryLabel)")
        }
        return DisplayRepresentation(title: "Restore no layout")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let preset else { return .result() }
        // Automatic, so like a schedule: skip a layout for other displays
        // rather than write its icons onto this desktop.
        let current = DisplayConfiguration.current()
        if let stored = PresetStore().find(id: preset.id), stored.categoryKey != current.key {
            Notifier.shared.notify(title: "Focus: skipped \u{201C}\(stored.name)\u{201D}",
                                   body: "It's for \(stored.displaySetupName), but you're on \(current.displayName).")
            return .result()
        }
        do {
            let message = try await LayoutRestorer.restore(id: preset.id)
            if UserDefaults.standard.showSuccessNotifications {
                Notifier.shared.notify(title: "Focus: restored \u{201C}\(preset.name)\u{201D}", body: message)
            }
        } catch {
            let reason = (error as? DesktopPresetIntentError).map { String(localized: $0.localizedStringResource) }
                ?? error.localizedDescription
            Notifier.shared.notify(title: "Couldn't restore \u{201C}\(preset.name)\u{201D}", body: reason)
        }
        return .result()
    }
}

// MARK: - Save

struct SaveArrangementIntent: AppIntent {
    static var title: LocalizedStringResource = "Save Desktop to Layout"
    static var description = IntentDescription(
        "Replaces a saved layout with your desktop as it is now. The layout must be for the displays you're using."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Layout")
    var preset: PresetEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = PresetStore()
        guard let stored = store.find(id: preset.id) else {
            throw DesktopPresetIntentError.presetNotFound
        }
        // Automation should be predictable: only overwrite a preset when the
        // current display setup matches its category. Cross-setup saves go
        // through the menu bar app's confirmation flow instead.
        let current = DisplayConfiguration.current()
        guard stored.categoryKey == current.key else {
            throw DesktopPresetIntentError.wrongDisplaySetup(
                presetLabel: stored.displaySetupName,
                currentLabel: current.displayName
            )
        }
        let snapshot = try IconArrangement.snapshot()
        let arrangement = DisplayArrangement(placements: CoreGraphicsDisplaySystem().currentPlacements())
        try store.updatePositions(id: stored.id, positions: snapshot.positions,
                                  displayArrangement: arrangement)
        NSLog("DeskStop AppIntent saved \(snapshot.positions.count) positions into '\(stored.name)'")
        return .result(dialog: "Saved \(snapshot.positions.count) icon positions to \u{201C}\(stored.name)\u{201D}.")
    }
}

// MARK: - App Shortcuts (zero-config Shortcuts entries)

struct DeskStopShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RestorePresetIntent(),
            phrases: [
                "Restore a layout in \(.applicationName)",
                "Restore my desktop with \(.applicationName)"
            ],
            shortTitle: "Restore Layout",
            systemImageName: "arrow.counterclockwise"
        )
        AppShortcut(
            intent: SaveArrangementIntent(),
            phrases: [
                "Save my desktop layout in \(.applicationName)"
            ],
            shortTitle: "Save Layout",
            systemImageName: "square.and.arrow.down"
        )
    }
}

#endif
