import Foundation
import DisplayCore

final class PresetStore {
    private let directory: URL

    init() {
        directory = DataFolder.url.appendingPathComponent("presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Storage paths

    /// Presets live in files named `{uuid}.json`.
    private func url(forID id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - Reading

    func list() -> [Preset] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let presets: [Preset] = urls.compactMap { u in
            guard u.pathExtension == "json",
                  isUUIDFilename(u),
                  let data = try? Data(contentsOf: u),
                  let p = try? JSONDecoder().decode(Preset.self, from: data) else { return nil }
            return p
        }
        return presets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Presets grouped by `categoryKey`, with each group sorted by name and
    /// the outer dictionary preserving insertion order via a paired array.
    /// First element of each tuple is a representative `(key, label)` for
    /// the category — label is taken from the first preset in the group.
    func presetsByCategory() -> [(key: String, label: String, presets: [Preset])] {
        var groups: [String: (label: String, presets: [Preset])] = [:]
        for p in list() {
            if var existing = groups[p.categoryKey] {
                existing.presets.append(p)
                groups[p.categoryKey] = existing
            } else {
                groups[p.categoryKey] = (label: p.displaySetupName, presets: [p])
            }
        }
        return groups
            .map { (key: $0.key, label: $0.value.label,
                    presets: LayoutOrder.sorted($0.value.presets, forSetup: $0.key)) }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    func find(id: UUID) -> Preset? {
        guard let data = try? Data(contentsOf: url(forID: id)),
              let p = try? JSONDecoder().decode(Preset.self, from: data) else { return nil }
        return p
    }

    func nameExists(_ name: String, inCategory categoryKey: String, excluding excludeID: UUID? = nil) -> Bool {
        list().contains { p in
            p.categoryKey == categoryKey &&
            p.name.caseInsensitiveCompare(name) == .orderedSame &&
            p.id != excludeID
        }
    }

    // MARK: - Writing

    func save(_ preset: Preset) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preset)
        try data.write(to: url(forID: preset.id), options: .atomic)
    }

    /// Create a new preset capturing `positions` for `configuration`.
    /// Returns the freshly minted preset so callers can immediately update
    /// any downstream state (e.g. hotkey config).
    @discardableResult
    func createNew(name: String,
                   positions: [IconPosition],
                   configuration: DisplayConfiguration,
                   restoreIconPositions: Bool? = nil,
                   displayArrangement: DisplayArrangement? = nil,
                   restoreDisplayArrangement: Bool? = nil,
                   restoreDisplayModes: Bool? = nil) throws -> Preset {
        let preset = Preset(name: name,
                            categoryKey: configuration.key,
                            categoryLabel: configuration.label,
                            positions: positions,
                            restoreIconPositions: restoreIconPositions,
                            displayArrangement: displayArrangement,
                            restoreDisplayArrangement: restoreDisplayArrangement,
                            restoreDisplayModes: restoreDisplayModes)
        try save(preset)
        return preset
    }

    /// Overwrite the positions on an existing preset ("Update from Current
    /// Desktop"), keeping its name, id and category. A non-nil `displayArrangement`
    /// updates the captured display layout too; nil leaves the existing one alone.
    func updatePositions(id: UUID, positions: [IconPosition], displayArrangement: DisplayArrangement? = nil) throws {
        guard var preset = find(id: id) else {
            throw makeError("Layout \(id) not found")
        }
        preset.positions = positions
        if let displayArrangement {
            preset.displayArrangement = displayArrangement
        }
        try save(preset)
    }

    func updateApps(id: UUID, apps: [SavedApp]?) throws {
        guard var preset = find(id: id) else {
            throw makeError("Layout \(id) not found")
        }
        preset.apps = apps
        try save(preset)
    }

    func updateLaunchAppsOnRestore(id: UUID, enabled: Bool) throws {
        guard var preset = find(id: id) else {
            throw makeError("Layout \(id) not found")
        }
        preset.launchAppsOnRestore = enabled
        try save(preset)
    }

    func updateRestoreDisplayArrangement(id: UUID, enabled: Bool) throws {
        guard var preset = find(id: id) else {
            throw makeError("Layout \(id) not found")
        }
        preset.restoreDisplayArrangement = enabled
        try save(preset)
    }

    func updateRestoreDisplayModes(id: UUID, enabled: Bool) throws {
        guard var preset = find(id: id) else {
            throw makeError("Layout \(id) not found")
        }
        preset.restoreDisplayModes = enabled
        try save(preset)
    }

    func updateRestoreIconPositions(id: UUID, enabled: Bool) throws {
        guard var preset = find(id: id) else {
            throw makeError("Layout \(id) not found")
        }
        preset.restoreIconPositions = enabled
        try save(preset)
    }

    func rename(id: UUID, to newName: String) throws {
        guard var preset = find(id: id) else {
            throw makeError("Layout \(id) not found")
        }
        preset.name = newName
        try save(preset)
    }

    func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: url(forID: id))
    }

    // MARK: - Import

    /// A copy of a layout for the same display setup: its icon positions,
    /// display arrangement, saved apps and restore options, under a new id and
    /// the name "<name> copy" (numbered if that's taken). Its shortcut and
    /// auto-restore choice stay with the original.
    @discardableResult
    func duplicate(id: UUID) throws -> Preset {
        guard var copy = find(id: id) else {
            throw makeError("Layout \(id) not found")
        }
        copy.id = UUID()
        let base = "\(copy.name) copy"
        if nameExists(base, inCategory: copy.categoryKey) {
            var i = 2
            while nameExists("\(base) \(i)", inCategory: copy.categoryKey) { i += 1 }
            copy.name = "\(base) \(i)"
        } else {
            copy.name = base
        }
        try save(copy)
        return copy
    }

    private func uniqueName(base: String, inCategory key: String) -> String {
        var i = 2
        var candidate = "\(base) (\(i))"
        while nameExists(candidate, inCategory: key) {
            i += 1
            candidate = "\(base) (\(i))"
        }
        return candidate
    }

    // MARK: - Helpers

    private func isUUIDFilename(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent
        return UUID(uuidString: stem) != nil
    }

    private func makeError(_ message: String) -> NSError {
        NSError(domain: "DeskStop.PresetStore", code: -1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
