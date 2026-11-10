import AppKit
import PresentationCore

/// An opaque, click-through window that covers one screen to hide its desktop
/// icons: above the icon layer, below app windows.
///
/// It shows the picture the user chose (`HiddenIconsCover`), else the screen's
/// wallpaper as captured (`WallpaperCapture`). Only if that fails does it draw
/// the wallpaper's file, which can be the wrong frame of a dynamic wallpaper.
final class DesktopOverlayWindow: NSPanel, DesktopOverlay {
    /// `picture`: the user's chosen picture, or nil for the wallpaper.
    init(screen: NSScreen, picture: URL?) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = true
        hasShadow = false
        // Swallow clicks on the empty desktop so hidden folders don't open. As a
        // non-activating panel it intercepts the click without stealing focus
        // from the user's frontmost app.
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // `.stationary` makes the overlay behave like the desktop during
        // Exposé/Mission Control (not animated away), reducing the brief flash
        // of the real icons during Space transitions.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        content.layer?.masksToBounds = true
        let pixels = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                            height: screen.frame.height * screen.backingScaleFactor)
        if let picture, let image = HiddenIconsCover.image(at: picture, filling: pixels) {
            // Fills the screen as a wallpaper set to Fill Screen would.
            backgroundColor = .black
            content.layer?.contentsGravity = .resizeAspectFill
            content.layer?.contents = image
        } else if let captured = WallpaperCapture.image(for: screen) {
            // Already the screen's exact size and shape.
            backgroundColor = .black
            content.layer?.contentsGravity = .resize
            content.layer?.contents = captured
        } else {
            backgroundColor = Self.drawWallpaperFile(for: screen, into: content)
        }
        contentView = content
        setFrame(screen.frame, display: true)
    }

    /// The fallback: the wallpaper's file, scaled as the screen's wallpaper
    /// settings say. Returns the colour around it, for the window.
    private static func drawWallpaperFile(for screen: NSScreen, into content: NSView) -> NSColor {
        // Replicate the user's actual desktop settings — scaling mode, fill
        // color, and clipping — rather than assuming "Fill Screen". This makes
        // Fit/Center/Stretch wallpapers (with a surround color) match too.
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let fillColor = (options[.fillColor] as? NSColor) ?? .black
        let scaling = (options[.imageScaling] as? NSNumber)
            .flatMap { NSImageScaling(rawValue: UInt(truncating: $0)) }
        let allowClipping = (options[.allowClipping] as? NSNumber)?.boolValue ?? true

        content.layer?.backgroundColor = fillColor.cgColor
        content.layer?.contentsGravity = gravity(for: scaling, allowClipping: allowClipping)
        if let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let image = NSImage(contentsOf: url) {
            var rect = NSRect(origin: .zero, size: image.size)
            content.layer?.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return fillColor
    }

    // Never take key/main status — the overlay only swallows clicks, it doesn't
    // need keyboard focus, and this guards against any focus disruption.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present() { orderFrontRegardless() }
    func dismiss() { orderOut(nil) }

    /// Maps a macOS desktop-image scaling mode to the equivalent CALayer
    /// contents gravity. `allowClipping` distinguishes Fill (crop) from Fit
    /// (letterbox with the surround fill color).
    private static func gravity(for scaling: NSImageScaling?,
                                allowClipping: Bool) -> CALayerContentsGravity {
        switch scaling {
        case .scaleAxesIndependently:
            return .resize                 // Stretch to fill
        case .scaleNone:
            return .center                 // Center at native size (and Tile, approx)
        default:
            return allowClipping ? .resizeAspectFill : .resizeAspect  // Fill vs Fit
        }
    }
}
