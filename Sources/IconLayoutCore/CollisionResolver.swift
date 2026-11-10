import Foundation

/// One desktop icon at a Finder `desktop position`.
public struct IconSpot: Equatable {
    public let name: String
    public let x: Double
    public let y: Double

    public init(name: String, x: Double, y: Double) {
        self.name = name
        self.x = x
        self.y = y
    }
}

/// The size of one icon slot on the desktop: icon, label and spacing.
public struct GridPitch: Equatable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// A rectangle in Finder desktop coordinates, y growing downwards.
public struct DesktopArea: Equatable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    func contains(_ x: Double, _ y: Double) -> Bool {
        x >= minX && x <= maxX && y >= minY && y <= maxY
    }
}

/// Decides where to move icons that a restore left sitting underneath a
/// restored icon.
///
/// A restore only moves the icons saved in the configuration. Anything added
/// to the desktop since keeps its place, and if a restored icon lands on that
/// place the two are drawn on top of each other. This finds those icons and a
/// free slot for each, nearest first. Restored icons are never moved: the
/// configuration is what the user asked for.
public enum CollisionResolver {
    /// Two icons overlap when they are less than one slot apart on both axes.
    public static func overlaps(_ a: IconSpot, _ b: IconSpot, pitch: GridPitch) -> Bool {
        abs(a.x - b.x) < pitch.width && abs(a.y - b.y) < pitch.height
    }

    /// New positions for the icons in `others` that overlap one in `restored`.
    ///
    /// - Parameters:
    ///   - restored: where the configuration's icons ended up.
    ///   - others: every other icon on the desktop, where it is now.
    ///   - area: where a moved icon may be put. Candidates outside it are
    ///     skipped, so nothing is pushed off screen.
    /// - Returns: one entry per icon to move. An overlapping icon with no free
    ///   slot inside `area` is left where it is and omitted.
    public static func relocations(restored: [IconSpot],
                                   others: [IconSpot],
                                   pitch: GridPitch,
                                   area: DesktopArea) -> [IconSpot] {
        guard pitch.width > 0, pitch.height > 0 else { return [] }

        let colliding = others.filter { other in
            restored.contains { overlaps($0, other, pitch: pitch) }
        }
        guard !colliding.isEmpty else { return [] }

        let collidingNames = Set(colliding.map(\.name))
        // Slots already spoken for: every restored icon, every icon that is
        // staying put, and each new home as it is handed out.
        var occupied = restored + others.filter { !collidingNames.contains($0.name) }

        // Widest search that can still land inside `area`.
        let maxRing = Int(max((area.maxX - area.minX) / pitch.width,
                              (area.maxY - area.minY) / pitch.height).rounded(.up)) + 1

        var moves: [IconSpot] = []
        // Sorted so the same desktop always resolves the same way.
        for icon in colliding.sorted(by: { $0.name < $1.name }) {
            guard let slot = nearestFreeSlot(around: icon, occupied: occupied,
                                             pitch: pitch, area: area, maxRing: maxRing)
            else { continue }
            moves.append(slot)
            occupied.append(slot)
        }
        return moves
    }

    /// Searches outward from `icon` one ring of slots at a time, keeping the
    /// icon on its own grid alignment, and returns the closest free slot.
    private static func nearestFreeSlot(around icon: IconSpot,
                                        occupied: [IconSpot],
                                        pitch: GridPitch,
                                        area: DesktopArea,
                                        maxRing: Int) -> IconSpot? {
        guard maxRing >= 1 else { return nil }
        for ring in 1...maxRing {
            var candidates: [(distance: Double, spot: IconSpot)] = []
            for dy in -ring...ring {
                for dx in -ring...ring where max(abs(dx), abs(dy)) == ring {
                    let x = icon.x + Double(dx) * pitch.width
                    let y = icon.y + Double(dy) * pitch.height
                    guard area.contains(x, y) else { continue }
                    let spot = IconSpot(name: icon.name, x: x, y: y)
                    guard !occupied.contains(where: { overlaps($0, spot, pitch: pitch) }) else { continue }
                    let distance = (Double(dx) * pitch.width) * (Double(dx) * pitch.width)
                        + (Double(dy) * pitch.height) * (Double(dy) * pitch.height)
                    candidates.append((distance, spot))
                }
            }
            // Nearest first; ties broken by position so the result is stable.
            if let best = candidates.min(by: {
                ($0.distance, $0.spot.x, $0.spot.y) < ($1.distance, $1.spot.x, $1.spot.y)
            }) {
                return best.spot
            }
        }
        return nil
    }
}
