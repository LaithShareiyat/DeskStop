import Foundation

/// How a layout's optional payloads resolve when their stored flag is absent.
///
/// The rules are deliberately not uniform:
///
/// - Icon positions are on unless switched off, so an absent flag means **on**.
/// - The display arrangement, display modes and the app list are opt-ins, so
///   an absent flag means **off**.
///
/// Each rule also requires its payload to exist: a flag on a layout with
/// nothing captured is not actionable.
public enum RestoreFlags {

    /// Absent means ON.
    public static func restoresIconPositions(stored: Bool?, hasPositions: Bool) -> Bool {
        (stored ?? true) && hasPositions
    }

    /// Absent means OFF.
    public static func restoresDisplayArrangement(stored: Bool?, hasArrangement: Bool) -> Bool {
        (stored ?? false) && hasArrangement
    }

    /// Absent means OFF. A layout with no captured modes is off whatever the
    /// flag says.
    public static func restoresDisplayModes(stored: Bool?, hasModes: Bool) -> Bool {
        (stored ?? false) && hasModes
    }

    /// Absent means OFF.
    public static func launchesApps(stored: Bool?, hasApps: Bool) -> Bool {
        (stored ?? false) && hasApps
    }
}
