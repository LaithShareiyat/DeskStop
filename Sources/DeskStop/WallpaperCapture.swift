import AppKit
import CoreGraphics

/// The wallpaper exactly as a screen shows it right now, for the hide-icons
/// overlay to draw.
///
/// Read from the window the Dock draws each screen's wallpaper in, not from the
/// file: a dynamic wallpaper's file holds every frame and only the window knows
/// which is showing, and it has the right wallpaper for the current Space.
///
/// Capturing it needs no Screen Recording permission: macOS exempts it, as it
/// does an app's own windows (checked on macOS 15).
enum WallpaperCapture {

    /// Nil when there is no wallpaper window for the screen (a full-screen
    /// app's Space, say) or macOS won't capture it; the overlay then falls
    /// back to the wallpaper's file.
    static func image(for screen: NSScreen) -> CGImage? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let bounds = CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
        let iconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] ?? []

        // Front to back, so the first match is the one showing. Matched by
        // owner, layer and size rather than by name, which macOS has changed
        // between versions ("Desktop Picture", "Wallpaper-<id>").
        let wallpaper = windows.first { info in
            guard info[kCGWindowOwnerName as String] as? String == "Dock",
                  let layer = info[kCGWindowLayer as String] as? Int, layer < iconLevel,
                  let frameInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: frameInfo as CFDictionary)
            else { return false }
            return frame == bounds
        }
        // shortcut: deprecated API, but ScreenCaptureKit would need Screen Recording permission.
        guard let id = wallpaper?[kCGWindowNumber as String] as? CGWindowID,
              let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id,
                                                  [.bestResolution, .boundsIgnoreFraming]),
              !isBlank(image)
        else { return nil }
        return image
    }

    /// A capture macOS declines can come back as an empty, fully transparent
    /// image rather than nil. Drawing that would hide the icons behind black.
    private static func isBlank(_ image: CGImage) -> Bool {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let pixel = context.data else { return false }
        return pixel.load(fromByteOffset: 3, as: UInt8.self) == 0
    }
}
