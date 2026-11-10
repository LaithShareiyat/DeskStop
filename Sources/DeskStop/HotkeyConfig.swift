import Foundation

struct HotkeyChord: Codable, Equatable {
    /// Carbon virtual key code (kVK_*).
    let keyCode: UInt32
    /// Raw Carbon modifier flag bits (cmdKey | optionKey | controlKey | shiftKey).
    let modifiers: UInt32
}

final class HotkeyConfigStore {
    private let fileURL: URL
    /// Keys are preset UUID strings.
    private var map: [String: HotkeyChord]

    init() {
        let dir = DataFolder.ensured()
        self.fileURL = dir.appendingPathComponent("hotkeys.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: HotkeyChord].self, from: data) {
            self.map = decoded
        } else {
            self.map = [:]
        }
    }

    func all() -> [String: HotkeyChord] { map }

    /// Merge imported bindings in (imported win on conflict). Config import.
    func merge(_ incoming: [String: HotkeyChord]) {
        for (k, v) in incoming { map[k] = v }
        persist()
    }

    func chord(forPresetID id: UUID) -> HotkeyChord? {
        map[id.uuidString]
    }

    /// Returns the preset ID currently bound to `chord`, if any.
    func presetBound(to chord: HotkeyChord, excluding excludeID: UUID? = nil) -> String? {
        map.first(where: { $0.value == chord && $0.key != excludeID?.uuidString })?.key
    }

    func set(_ chord: HotkeyChord, forPresetID id: UUID) {
        map[id.uuidString] = chord
        persist()
    }

    func clear(forPresetID id: UUID) {
        map.removeValue(forKey: id.uuidString)
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(map) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

extension UserDefaults {
    private static let hideDesktopHotkeyKey = "hideDesktopHotkey"
    private static let cyclePresetsHotkeyKey = "cyclePresetsHotkey"

    /// The global chord that toggles Hide Desktop Icons, or nil if unset.
    var hideDesktopHotkey: HotkeyChord? {
        get { chord(forKey: Self.hideDesktopHotkeyKey) }
        set { setChord(newValue, forKey: Self.hideDesktopHotkeyKey) }
    }

    /// The global chord that cycles through the current display's presets.
    var cyclePresetsHotkey: HotkeyChord? {
        get { chord(forKey: Self.cyclePresetsHotkeyKey) }
        set { setChord(newValue, forKey: Self.cyclePresetsHotkeyKey) }
    }

    private func chord(forKey key: String) -> HotkeyChord? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeyChord.self, from: data)
    }

    private func setChord(_ chord: HotkeyChord?, forKey key: String) {
        if let chord = chord, let data = try? JSONEncoder().encode(chord) {
            set(data, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
