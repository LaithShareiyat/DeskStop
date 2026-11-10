import Foundation

/// One display's resolution, scaling and refresh rate: a CoreGraphics display
/// mode, kept by what can be seen of it rather than by its id, which is only
/// meaningful to the display and connection it came from.
///
/// `width` × `height` is the size in points, what System Settings shows as
/// "Looks like". `pixelWidth` × `pixelHeight` is the size the display is
/// driven at, twice the points for a sharp (HiDPI) scaled mode, so the two
/// together are the scaling.
public struct DisplayMode: Codable, Equatable {
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// In hertz. Some displays, built-in ones especially, report 0.
    public let refreshRate: Double

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }

    /// The same mode as far as anyone could tell: same size and scaling, and
    /// a refresh rate within half a hertz (displays report 59.94 for 60).
    public func isSame(as other: DisplayMode) -> Bool {
        hasSameResolution(as: other) && abs(refreshRate - other.refreshRate) < 0.5
    }

    private func hasSameResolution(as other: DisplayMode) -> Bool {
        width == other.width && height == other.height
            && pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight
    }

    /// "1512 × 982, 120 Hz", or without the rate when the display reports none.
    public var summary: String {
        let size = "\(width) × \(height)"
        guard refreshRate > 0 else { return size }
        return "\(size), \(Int(refreshRate.rounded())) Hz"
    }

    /// The mode in `available` that best stands for `saved`: the same size
    /// and scaling, at the nearest refresh rate (the higher of two equally
    /// near). Nil when the display can't show that resolution at all, for
    /// example through a dock or cable that can't carry it.
    public static func bestMatch(for saved: DisplayMode, in available: [DisplayMode]) -> DisplayMode? {
        available
            .filter { $0.hasSameResolution(as: saved) }
            .min { a, b in
                let da = abs(a.refreshRate - saved.refreshRate)
                let db = abs(b.refreshRate - saved.refreshRate)
                return da == db ? a.refreshRate > b.refreshRate : da < db
            }
    }
}
