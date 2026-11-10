import AppKit
import CoreGraphics
import DisplayCore

/// The real `DisplaySystem`: reads display positions and modes from
/// CoreGraphics and writes them back as a single display-configuration
/// transaction.
///
/// Positions come from `CGDisplayBounds`, never `NSScreen.frame`. The two
/// disagree on Y direction — AppKit is bottom-left origin with Y up, CG is
/// top-left origin with Y down — and `CGConfigureDisplayOrigin` expects CG
/// space. Reading from AppKit here would silently invert the layout of any
/// display stacked above or below another.
struct CoreGraphicsDisplaySystem: DisplaySystem {

    enum Failure: Error, CustomStringConvertible {
        case couldNotBegin(CGError)
        case unknownDisplay(uuid: String)
        case couldNotSetOrigin(CGError, uuid: String)
        case modeNotOffered(uuid: String, mode: DisplayMode)
        case couldNotSetMode(CGError, uuid: String)
        case couldNotCommit(CGError)

        var description: String {
            switch self {
            case .couldNotBegin(let e):
                return "couldn't begin a display configuration (CGError \(e.rawValue))"
            case .unknownDisplay(let uuid):
                return "display \(uuid) is not attached"
            case .couldNotSetOrigin(let e, let uuid):
                return "couldn't position display \(uuid) (CGError \(e.rawValue))"
            case .modeNotOffered(let uuid, let mode):
                return "display \(uuid) doesn't offer \(mode.summary)"
            case .couldNotSetMode(let e, let uuid):
                return "couldn't set the resolution of display \(uuid) (CGError \(e.rawValue))"
            case .couldNotCommit(let e):
                return "couldn't commit the display configuration (CGError \(e.rawValue))"
            }
        }
    }

    func currentPlacements() -> [DisplayArrangement.Placement] {
        DisplayIdentity.activeDisplayIDs().compactMap { id in
            guard let uuid = DisplayIdentity.uuid(for: id) else { return nil }
            let origin = CGDisplayBounds(id).origin
            return DisplayArrangement.Placement(
                uuid: uuid,
                x: Int32(origin.x.rounded()),
                y: Int32(origin.y.rounded()),
                name: DisplayIdentity.name(for: id),
                mode: CGDisplayCopyDisplayMode(id).map(Self.mode(of:)))
        }
    }

    func availableModes(forDisplay uuid: String) -> [DisplayMode] {
        guard let id = DisplayIdentity.displayID(forUUID: uuid) else { return [] }
        return Self.offeredModes(id).map(Self.mode(of:))
    }

    func apply(origins: [DisplayArrangement.Placement], modes: [String: DisplayMode]) throws {
        // Resolve every display and mode before opening the transaction, so
        // a missing one cannot leave a transaction dangling.
        var resolved: [(id: CGDirectDisplayID, placement: DisplayArrangement.Placement)] = []
        for placement in origins {
            guard let id = DisplayIdentity.displayID(forUUID: placement.uuid) else {
                throw Failure.unknownDisplay(uuid: placement.uuid)
            }
            resolved.append((id, placement))
        }
        var resolvedModes: [(id: CGDirectDisplayID, uuid: String, mode: CGDisplayMode)] = []
        for (uuid, wanted) in modes.sorted(by: { $0.key < $1.key }) {
            guard let id = DisplayIdentity.displayID(forUUID: uuid) else {
                throw Failure.unknownDisplay(uuid: uuid)
            }
            // Closest rate among the matches: a display can offer both 60 and
            // 59.94 Hz, which `isSame` can't tell apart.
            guard let mode = Self.offeredModes(id)
                .filter({ Self.mode(of: $0).isSame(as: wanted) })
                .min(by: { abs($0.refreshRate - wanted.refreshRate) < abs($1.refreshRate - wanted.refreshRate) })
            else {
                throw Failure.modeNotOffered(uuid: uuid, mode: wanted)
            }
            resolvedModes.append((id, uuid, mode))
        }

        var config: CGDisplayConfigRef?
        let began = CGBeginDisplayConfiguration(&config)
        guard began == .success, let config else { throw Failure.couldNotBegin(began) }

        // Modes before origins: a new resolution changes a display's size,
        // and the origins are what the arrangement says once it has.
        for entry in resolvedModes {
            let error = CGConfigureDisplayWithDisplayMode(config, entry.id, entry.mode, nil)
            guard error == .success else {
                CGCancelDisplayConfiguration(config)
                throw Failure.couldNotSetMode(error, uuid: entry.uuid)
            }
        }

        for entry in resolved {
            let error = CGConfigureDisplayOrigin(config, entry.id, entry.placement.x, entry.placement.y)
            guard error == .success else {
                // Abandon the whole transaction — never commit a partial layout.
                CGCancelDisplayConfiguration(config)
                throw Failure.couldNotSetOrigin(error, uuid: entry.placement.uuid)
            }
        }

        // kCGConfigurePermanently: persist like System Settings does. A
        // session-scoped change that silently reverted at logout would be a
        // worse surprise than the risk it avoids, and ArrangementPolicy's
        // rollback covers the failure case.
        let committed = CGCompleteDisplayConfiguration(config, .permanently)
        guard committed == .success else { throw Failure.couldNotCommit(committed) }
    }

    /// The modes System Settings would list for the display, sharp (HiDPI)
    /// scaled ones included, which CoreGraphics leaves out unless asked.
    private static func offeredModes(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let all = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
        return all.filter { $0.isUsableForDesktopGUI() }
    }

    private static func mode(of mode: CGDisplayMode) -> DisplayMode {
        DisplayMode(width: mode.width, height: mode.height,
                    pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight,
                    refreshRate: mode.refreshRate)
    }
}
