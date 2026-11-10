import CoreGraphics

/// Where the menu bar panel hangs from, in AppKit screen coordinates
/// (origin bottom-left of the primary screen, y up).
///
/// The panel is pinned to the icon's position at the moment it opens rather
/// than to the status item itself: over a full-screen app the menu bar slides
/// out of view once the pointer leaves it, and a panel attached to the status
/// item went with it, cut off by the top of the screen.
public enum StatusItemAnchor {
    /// The icon's rect while its menu bar is showing. If the bar had already
    /// slid away (the icon sits above the top of its screen), the rect moves
    /// down to that screen's top edge, where the bar shows when it is in view.
    public static func anchorRect(iconRect: CGRect, screenFrames: [CGRect]) -> CGRect {
        // The screen whose menu bar holds the icon: it spans the icon's x, and
        // of those (screens stacked vertically) its top is nearest the icon.
        let candidates = screenFrames.filter { $0.minX <= iconRect.midX && iconRect.midX < $0.maxX }
        guard let screen = candidates.min(by: {
            abs($0.maxY - iconRect.maxY) < abs($1.maxY - iconRect.maxY)
        }) else { return iconRect }
        var anchor = iconRect
        anchor.origin.y = min(iconRect.minY, screen.maxY - iconRect.height)
        return anchor
    }
}
