import Foundation

/// The default layout per display setup, which auto-restore runs on
/// dock/undock. Stored as one JSON `[String: String]` (setup key → layout UUID)
/// in UserDefaults.
final class DefaultPresetStore {

    private let key = "defaultPresetsByCategory"
    private var map: [String: String]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.map = decoded
        } else {
            self.map = [:]
        }
    }

    func defaultPreset(forCategory categoryKey: String) -> UUID? {
        guard let s = map[categoryKey], let id = UUID(uuidString: s) else { return nil }
        return id
    }

    func isDefault(presetID: UUID, forCategory categoryKey: String) -> Bool {
        defaultPreset(forCategory: categoryKey) == presetID
    }

    func setDefault(presetID: UUID, forCategory categoryKey: String) {
        map[categoryKey] = presetID.uuidString
        persist()
    }

    /// Toggle a preset's default flag for its category. Returns the new state.
    @discardableResult
    func toggleDefault(presetID: UUID, forCategory categoryKey: String) -> Bool {
        if isDefault(presetID: presetID, forCategory: categoryKey) {
            map.removeValue(forKey: categoryKey)
            persist()
            return false
        } else {
            setDefault(presetID: presetID, forCategory: categoryKey)
            return true
        }
    }

    /// Drop any default entries that point at the given preset ID. Called
    /// when a preset is deleted so we don't leak a dangling reference.
    func clearAnyReferencesTo(presetID: UUID) {
        let s = presetID.uuidString
        let toRemove = map.filter { $0.value == s }.map { $0.key }
        guard !toRemove.isEmpty else { return }
        for k in toRemove { map.removeValue(forKey: k) }
        persist()
    }

    /// Raw category-key → preset-UUID map, for configuration export.
    func exportMap() -> [String: String] { map }

    /// Merge an imported map in (imported entries win). Used by config import.
    func merge(_ incoming: [String: String]) {
        for (k, v) in incoming { map[k] = v }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

