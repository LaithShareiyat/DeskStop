import Foundation
import IconLayoutCore

struct FinderDesktopSettings {
    /// `none`, `grid`, `name`, `dateModified`, `dateCreated`, `size`, `kind`, `label`
    let arrangeBy: String
    /// `None` means Stacks is OFF. Any other value (e.g. `Kind`, `DateLastOpened`) means Stacks is ON.
    let groupBy: String

    /// True when AppleScript `set position` will actually stick on the Desktop.
    var positionsAreEditable: Bool {
        groupBy == "None" && (arrangeBy == "none" || arrangeBy == "grid")
    }
}

/// The Desktop's icon view sizes, from Finder's View Options.
struct FinderIconLayout {
    let iconSize: Double
    let textSize: Double

    /// One icon slot: the icon, up to two lines of label, and a margin.
    ///
    /// Deliberately on the small side of Finder's grid: a larger slot would flag
    /// icons sitting neatly side by side. Too small only leaves a moved icon a
    /// little close to its neighbour, which Snap to Grid tidies.
    var pitch: GridPitch {
        GridPitch(width: iconSize + 20, height: iconSize + textSize * 2 + 20)
    }
}

enum FinderSettings {
    /// Falls back to Finder's defaults (64 pt icons, 12 pt labels) for any
    /// value the user has never changed, since Finder doesn't store those.
    static func readIconLayout() -> FinderIconLayout {
        let raw = runDefaultsRead(domain: "com.apple.finder", key: "DesktopViewSettings") ?? ""
        let iconSize = parseValue(in: raw, key: "iconSize").flatMap(Double.init) ?? 64
        let textSize = parseValue(in: raw, key: "textSize").flatMap(Double.init) ?? 12
        return FinderIconLayout(iconSize: iconSize, textSize: textSize)
    }

    static func read() -> FinderDesktopSettings {
        let raw = runDefaultsRead(domain: "com.apple.finder", key: "DesktopViewSettings") ?? ""
        let arrangeBy = parseValue(in: raw, key: "arrangeBy") ?? "none"
        let groupBy = parseValue(in: raw, key: "GroupBy") ?? "None"
        return FinderDesktopSettings(arrangeBy: arrangeBy, groupBy: groupBy)
    }

    private static func runDefaultsRead(domain: String, key: String) -> String? {
        let process = Process()
        process.launchPath = "/usr/bin/defaults"
        process.arguments = ["read", domain, key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Parses lines like `    arrangeBy = grid;` out of a `defaults read` plist dump.
    private static func parseValue(in dump: String, key: String) -> String? {
        for line in dump.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key) =") else { continue }
            let after = trimmed.dropFirst("\(key) =".count)
            return after
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ";\""))
        }
        return nil
    }
}
