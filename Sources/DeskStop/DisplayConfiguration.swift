import AppKit
import CoreGraphics

/// Identifies the physical set of displays currently attached, stable across
/// reboots and replugs because it keys off each display's UUID rather than its
/// session-scoped CGDirectDisplayID. The same displays give the same `key`.
struct DisplayConfiguration: Codable, Equatable {
    /// Sorted list of display UUIDs (lowercased) — the canonical fingerprint.
    let displayUUIDs: [String]
    /// Human-friendly label like "Built-in" or "Built-in + DELL U2719D".
    let label: String

    /// The string we actually persist in `PresetVariant.configurationKey`.
    /// Same UUIDs → same key, regardless of which one became display 1
    /// after a replug.
    var key: String { displayUUIDs.joined(separator: "|") }

    static let unknown = DisplayConfiguration(displayUUIDs: [], label: "Unknown")

    /// Snapshot the current display arrangement.
    static func current() -> DisplayConfiguration {
        let screens = NSScreen.screens
        var entries: [(uuid: String, name: String, isBuiltin: Bool)] = []

        for screen in screens {
            let id = DisplayIdentity.displayID(for: screen)
            let uuid = DisplayIdentity.uuid(for: id) ?? "screen-\(id)"
            let name = screen.localizedName
            let builtin = id != 0 && CGDisplayIsBuiltin(id) != 0
            entries.append((uuid, name, builtin))
        }

        let sortedUUIDs = entries.map { $0.uuid }.sorted()
        return DisplayConfiguration(
            displayUUIDs: sortedUUIDs,
            label: buildLabel(entries: entries)
        )
    }

    /// Build a label that puts the built-in display first, then any externals.
    private static func buildLabel(entries: [(uuid: String, name: String, isBuiltin: Bool)]) -> String {
        if entries.isEmpty { return "No displays" }
        let builtins = entries.filter { $0.isBuiltin }.map { $0.name }
        let externals = entries.filter { !$0.isBuiltin }.map { $0.name }

        let parts = builtins + externals
        switch parts.count {
        case 1: return parts[0]
        case 2: return "\(parts[0]) + \(parts[1])"
        default:
            // Collapse externals when there are many to keep the label short.
            let head = parts.first ?? "Built-in"
            return "\(head) + \(parts.count - 1) external displays"
        }
    }
}
