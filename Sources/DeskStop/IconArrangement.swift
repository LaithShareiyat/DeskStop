import Foundation
import IconLayoutCore

struct IconPosition: Codable {
    let name: String
    let x: Double
    let y: Double
}

struct SnapshotResult {
    let positions: [IconPosition]
    let settings: FinderDesktopSettings
}

struct RestoreResult {
    let attempted: Int
    let succeeded: Int
    /// Saved items that are no longer on the Desktop (deleted, renamed or
    /// moved away). Not included in `failed`.
    let missing: [String]
    /// Items that exist but Finder would not put where they were saved.
    let failed: [(name: String, reason: String)]
    /// Icons not in the configuration that a restored icon landed on, and
    /// that were moved to a free spot nearby.
    let movedAside: [String]
    let settings: FinderDesktopSettings

    /// Every item that did not end up where it was saved.
    var hasProblems: Bool { !missing.isEmpty || !failed.isEmpty }

    /// Every item that did not end up where it was saved, missing first.
    var problemNames: [String] { missing + failed.map(\.name) }

    /// "Couldn't restore “Projects”" — a notification or alert title
    /// naming what went wrong. Nil when nothing did.
    var problemTitle: String? {
        hasProblems ? "Couldn't restore \(Self.quotedList(problemNames))" : nil
    }

    /// Short sentences for a notification or dialog, naming the items
    /// involved. Empty when there is nothing to report.
    var notes: [String] {
        var lines: [String] = []
        if !missing.isEmpty {
            let verb = missing.count == 1 ? "is" : "are"
            lines.append("\(Self.quotedList(missing)) \(verb) no longer on the desktop.")
        }
        if !failed.isEmpty {
            lines.append("Finder wouldn't move \(Self.quotedList(failed.map(\.name))).")
        }
        if !movedAside.isEmpty {
            lines.append("Moved \(Self.quotedList(movedAside)) out of the way.")
        }
        return lines
    }

    /// “A”, “B” and “C”, or “A”, “B”, “C” and 4 more.
    static func quotedList(_ names: [String], limit: Int = 3) -> String {
        let quoted = names.prefix(limit).map { "\u{201C}\($0)\u{201D}" }
        if names.count > limit {
            return quoted.joined(separator: ", ") + " and \(names.count - limit) more"
        }
        if quoted.count <= 1 { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " and " + quoted.last!
    }
}

enum IconArrangement {
    // Field/row separators for the AppleScript output: ASCII unit and record
    // separators can't appear in a filename (the script binds the same as
    // `fs`/`rs`).
    private static let fieldSep: Character = "\u{1F}"
    private static let rowSep: Character = "\u{1E}"

    // MARK: - Snapshot

    static func snapshot() throws -> SnapshotResult {
        // Read `desktop position` (the rendered, multi-monitor-aware location), not
        // `position` (an internal cache that can diverge).
        let script = """
        set fs to character id 31
        set rs to character id 30
        set rows to ""
        tell application "Finder"
            set n to count items of desktop
            repeat with i from 1 to n
                set theItem to item i of desktop
                try
                    set p to missing value
                    try
                        set p to desktop position of theItem
                    end try
                    if p is missing value then
                        set p to position of theItem
                    end if
                    set rows to rows & (name of theItem) & fs & (item 1 of p) & fs & (item 2 of p) & rs
                end try
            end repeat
        end tell
        return rows
        """
        let raw = try runAppleScript(script)
        return SnapshotResult(
            positions: parsePositions(raw),
            settings: FinderSettings.read()
        )
    }

    // MARK: - Restore

    static func restore(positions: [IconPosition]) throws -> RestoreResult {
        let written = try write(positions)
        // Only after a restore that moved something: an all-missing restore
        // has put nothing on top of anything.
        let movedAside = written.succeeded.isEmpty
            ? []
            : clearOverlaps(restoredNames: Set(positions.map(\.name)))
        return RestoreResult(
            attempted: positions.count,
            succeeded: written.succeeded.count,
            missing: written.missing,
            failed: written.failed,
            movedAside: movedAside,
            settings: FinderSettings.read()
        )
    }

    private struct WriteResult {
        var succeeded: [String] = []
        var missing: [String] = []
        var failed: [(name: String, reason: String)] = []
    }

    /// Sets each item's `desktop position` and reads it back.
    private static func write(_ positions: [IconPosition]) throws -> WriteResult {
        var setLines: [String] = []
        for p in positions {
            let escaped = escapeForAppleScript(p.name)
            let wantX = Int(p.x)
            let wantY = Int(p.y)
            // Write `desktop position`, falling back to `position` for items that don't
            // support it. A vanished item is reported MISSING, not "couldn't be moved".
            setLines.append("""
            if not (exists item "\(escaped)" of desktop) then
                set resultLog to resultLog & "MISSING" & fs & "\(escaped)" & rs
            else
                try
                    try
                        set desktop position of (item "\(escaped)" of desktop) to {\(wantX), \(wantY)}
                    on error
                        set position of (item "\(escaped)" of desktop) to {\(wantX), \(wantY)}
                    end try
                    set actualP to missing value
                    try
                        set actualP to desktop position of (item "\(escaped)" of desktop)
                    end try
                    if actualP is missing value then
                        set actualP to position of (item "\(escaped)" of desktop)
                    end if
                    set ax to item 1 of actualP
                    set ay to item 2 of actualP
                    if ax = \(wantX) and ay = \(wantY) then
                        set resultLog to resultLog & "OK" & fs & "\(escaped)" & rs
                    else
                        set resultLog to resultLog & "MISMATCH" & fs & "\(escaped)" & fs & "want \(wantX),\(wantY) got " & (ax as text) & "," & (ay as text) & rs
                    end if
                on error errMsg
                    set resultLog to resultLog & "ERR" & fs & "\(escaped)" & fs & errMsg & rs
                end try
            end if
            """)
        }

        let script = """
        set fs to character id 31
        set rs to character id 30
        set resultLog to ""
        tell application "Finder"
        \(setLines.joined(separator: "\n"))
        end tell
        return resultLog
        """

        let raw = try runAppleScript(script)
        var result = WriteResult()
        for line in raw.split(separator: rowSep) {
            let cols = line.split(separator: fieldSep, omittingEmptySubsequences: false)
            guard cols.count >= 2 else { continue }
            let name = String(cols[1])
            switch cols[0] {
            case "OK":
                result.succeeded.append(name)
            case "MISSING":
                result.missing.append(name)
            case "MISMATCH":
                let reason = cols.count >= 3 ? "Finder accepted the change but didn't apply it (\(cols[2]))" : "snap/clamp"
                result.failed.append((name: name, reason: reason))
            case "ERR":
                let reason = cols.count >= 3 ? String(cols[2]) : "unknown"
                result.failed.append((name: name, reason: reason))
            default:
                break
            }
        }
        return result
    }

    // MARK: - Overlaps

    /// Moves icons that are not in the configuration out from under the
    /// restored ones. Best effort: a failure here is logged and the restore
    /// still counts, since every saved icon is already in place.
    /// Undo covers this too: every restore stashes the whole desktop first.
    private static func clearOverlaps(restoredNames: Set<String>) -> [String] {
        do {
            let spots = try snapshot().positions.map { IconSpot(name: $0.name, x: $0.x, y: $0.y) }
            let restored = spots.filter { restoredNames.contains($0.name) }
            let others = spots.filter { !restoredNames.contains($0.name) }
            guard !restored.isEmpty, !others.isEmpty else { return [] }

            let pitch = FinderSettings.readIconLayout().pitch
            let area = desktopArea(containing: spots, pitch: pitch)
            let moves = CollisionResolver.relocations(restored: restored, others: others,
                                                      pitch: pitch, area: area)
            guard !moves.isEmpty else { return [] }

            let written = try write(moves.map { IconPosition(name: $0.name, x: $0.x, y: $0.y) })
            // A MISMATCH here means Finder snapped the icon to its grid,
            // which still moved it off the restored one.
            let moved = written.succeeded + written.failed
                .filter { $0.reason.hasPrefix("Finder accepted") }
                .map(\.name)
            NSLog("DeskStop moved \(moved.count) overlapping icon(s) aside: \(moved)")
            return moved
        } catch {
            NSLog("DeskStop couldn't clear overlapping icons: \(error)")
            return []
        }
    }

    /// Where a moved icon may go: the desktop window's bounds, kept half a
    /// slot in from the edges, plus wherever icons already are (so an
    /// unusual coordinate space never shrinks the area to nothing).
    private static func desktopArea(containing spots: [IconSpot], pitch: GridPitch) -> DesktopArea {
        var minX = spots.map(\.x).min() ?? 0
        var minY = spots.map(\.y).min() ?? 0
        var maxX = spots.map(\.x).max() ?? 0
        var maxY = spots.map(\.y).max() ?? 0
        if let bounds = desktopBounds() {
            minX = min(minX, bounds.minX + pitch.width / 2)
            minY = min(minY, bounds.minY + pitch.height / 2)
            maxX = max(maxX, bounds.maxX - pitch.width / 2)
            maxY = max(maxY, bounds.maxY - pitch.height / 2)
        }
        return DesktopArea(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// Finder's `bounds of window of desktop`, or nil if it can't be read.
    private static func desktopBounds() -> DesktopArea? {
        let script = """
        set fs to character id 31
        tell application "Finder"
            set b to bounds of window of desktop
        end tell
        return ((item 1 of b) as text) & fs & ((item 2 of b) as text) & fs & ((item 3 of b) as text) & fs & ((item 4 of b) as text)
        """
        guard let raw = try? runAppleScript(script) else { return nil }
        let values = raw.split(separator: fieldSep).compactMap { Double($0) }
        guard values.count == 4, values[2] > values[0], values[3] > values[1] else { return nil }
        return DesktopArea(minX: values[0], minY: values[1], maxX: values[2], maxY: values[3])
    }

    // MARK: - Drift detection

    /// Reads current desktop positions and returns the subset of `expected`
    /// whose live position doesn't match — candidates for an iCloud override.
    static func findDrifted(against expected: [IconPosition]) -> [IconPosition] {
        guard let snap = try? snapshot() else { return [] }
        var actual: [String: (Int, Int)] = [:]
        for p in snap.positions {
            actual[p.name] = (Int(p.x), Int(p.y))
        }
        return expected.filter { exp in
            guard let (x, y) = actual[exp.name] else { return false }
            return x != Int(exp.x) || y != Int(exp.y)
        }
    }

    // MARK: - AppleScript helpers

    private static func runAppleScript(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw NSError(domain: "DeskStop.AppleScript", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to compile AppleScript"])
        }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            var info = err as? [String: Any] ?? [:]
            // -1743: the user hasn't allowed DeskStop to control Finder.
            info[NSLocalizedDescriptionKey] = err[NSAppleScript.errorNumber] as? Int == -1743
                ? "DeskStop isn't allowed to control Finder. Turn on Finder access in Settings › Permissions."
                : err[NSAppleScript.errorMessage] as? String ?? "Finder returned an error."
            throw NSError(domain: "DeskStop.AppleScript", code: -2, userInfo: info)
        }
        return result.stringValue ?? ""
    }

    private static func parsePositions(_ raw: String) -> [IconPosition] {
        raw.split(separator: rowSep).compactMap { line in
            let parts = line.split(separator: fieldSep, omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let x = Double(parts[1]),
                  let y = Double(parts[2]) else { return nil }
            return IconPosition(name: String(parts[0]), x: x, y: y)
        }
    }

    /// Escapes a Finder item name for embedding in an AppleScript string
    /// literal. Beyond quote/backslash (injection safety), newlines and tabs
    /// are escaped because a literal newline is a syntax error inside an
    /// AppleScript string and would break the generated script.
    private static func escapeForAppleScript(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
