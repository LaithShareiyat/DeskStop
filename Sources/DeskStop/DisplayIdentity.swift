import AppKit
import CoreGraphics

/// Mapping between `NSScreen`, session-scoped `CGDirectDisplayID`, and stable
/// display UUIDs.
///
/// UUIDs are the only identifier safe to persist: `CGDirectDisplayID` is
/// reassigned across replugs and reboots. Both UUID functions come from
/// ColorSync, which AppKit exposes transitively.
enum DisplayIdentity {

    /// `NSScreen` exposes the display ID via the private-but-stable
    /// `NSScreenNumber` key on `deviceDescription`.
    static func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let n = screen.deviceDescription[key] as? NSNumber else { return 0 }
        return CGDirectDisplayID(n.uint32Value)
    }

    static func uuid(for displayID: CGDirectDisplayID) -> String? {
        guard displayID != 0,
              let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return (CFUUIDCreateString(nil, uuidRef) as String?)?.lowercased()
    }

    /// Resolve a persisted UUID back to a live display ID.
    ///
    /// The result is checked against the active display list: a UUID for a
    /// display that is no longer attached must not resolve to something we
    /// would then try to move.
    static func displayID(forUUID uuid: String) -> CGDirectDisplayID? {
        guard let cfUUID = CFUUIDCreateFromString(nil, uuid as CFString) else { return nil }
        let id = CGDisplayGetDisplayIDFromUUID(cfUUID)
        guard id != 0, activeDisplayIDs().contains(id) else { return nil }
        return id
    }

    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Localized display name, via the `NSScreen` that backs this display.
    static func name(for displayID: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { self.displayID(for: $0) == displayID }?.localizedName
    }
}
