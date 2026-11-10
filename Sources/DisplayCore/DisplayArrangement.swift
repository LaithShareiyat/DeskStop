import Foundation

/// A physical display layout: where each display sits, and by implication which
/// one is main.
///
/// Coordinates are **CoreGraphics global coordinates** — top-left origin, Y
/// increasing downward — the same space `CGDisplayBounds` reports and
/// `CGConfigureDisplayOrigin` accepts. They are deliberately *not* AppKit
/// coordinates (`NSScreen.frame`), which are bottom-left origin with Y
/// increasing upward. Mixing the two silently inverts the layout of any display
/// stacked above or below another.
public struct DisplayArrangement: Codable, Equatable {

    /// One display's position within the arrangement.
    public struct Placement: Codable, Equatable {
        /// Stable display UUID — survives reboots and replugs, unlike
        /// `CGDirectDisplayID`.
        public let uuid: String
        public let x: Int32
        public let y: Int32
        /// Display name as seen at capture time, e.g. "DELL U2719D". For
        /// human-readable messages only: a disconnected display's name cannot
        /// be looked up from its UUID, so it must be captured up front.
        public let name: String?
        /// Resolution, scaling and refresh rate at capture time; nil if none was
        /// captured. Restored only when the layout opts in, separately from position.
        public let mode: DisplayMode?

        public init(uuid: String, x: Int32, y: Int32, name: String? = nil, mode: DisplayMode? = nil) {
            self.uuid = uuid
            self.x = x
            self.y = y
            self.name = name
            self.mode = mode
        }

        /// `name` is deliberately excluded. A monitor renamed between capture
        /// and restore is still the same monitor, and comparing on it would
        /// cause spurious rollbacks. `mode` is excluded too: this is the
        /// position, and `ArrangementPolicy` compares modes on its own, only
        /// when it was asked to restore them.
        public static func == (lhs: Placement, rhs: Placement) -> Bool {
            lhs.uuid == rhs.uuid && lhs.x == rhs.x && lhs.y == rhs.y
        }
    }

    /// Always sorted by `uuid`, so equality is order-insensitive and JSON
    /// diffs stay stable.
    public let placements: [Placement]

    /// The display at the origin. macOS defines the main display as the one at
    /// (0,0), so this is derived rather than stored — a stored copy could
    /// contradict `placements`.
    public var mainDisplayUUID: String? {
        placements.first { $0.x == 0 && $0.y == 0 }?.uuid
    }

    /// Whether resolution and refresh rate were captured with the positions.
    public var hasModes: Bool {
        placements.contains { $0.mode != nil }
    }

    /// The same positions with the modes left out, so applying it never
    /// changes a resolution.
    public var withoutModes: DisplayArrangement {
        DisplayArrangement(placements: placements.map {
            Placement(uuid: $0.uuid, x: $0.x, y: $0.y, name: $0.name)
        })
    }

    public init(placements: [Placement]) {
        self.placements = placements.sorted { $0.uuid < $1.uuid }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decode([Placement].self, forKey: .placements)
        self.placements = decoded.sorted { $0.uuid < $1.uuid }
    }

    private enum CodingKeys: String, CodingKey {
        case placements
    }
}
