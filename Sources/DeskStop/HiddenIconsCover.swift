import AppKit
import ImageIO

/// What hidden desktop icons sit behind, for Hide Desktop Icons and for
/// hiding them while screen sharing alike: a copy of the wallpaper (the
/// default, so the desktop looks the same) or a picture the user chose, so
/// it's plain at a glance that icons are hidden.
enum HiddenIconsCover {

    /// A picture decoded at the size that fills `size` (in pixels) rather
    /// than its own: a wallpaper file can be 6K square, and each screen's
    /// cover holds its own copy while icons are hidden.
    static func image(at url: URL, filling size: CGSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        // Orientations 5 to 8 turn the picture on its side.
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue,
           (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let fill = max(size.width / width, size.height / height)
        let longest = max(width, height)
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(longest, (longest * fill).rounded(.up)),
        ] as CFDictionary)
    }

    /// A small preview for the picture gallery. Uses the preview stored in
    /// the file when there is one, which is far quicker than decoding a 6K
    /// wallpaper.
    static func thumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary)
    }
}

extension UserDefaults {
    private static let hiddenIconsPictureKey = "hiddenIconsCoverPicture"

    /// The picture hidden icons sit behind; nil for the wallpaper.
    var hiddenIconsPicture: URL? {
        get { string(forKey: Self.hiddenIconsPictureKey).map { URL(fileURLWithPath: $0) } }
        set { set(newValue?.path, forKey: Self.hiddenIconsPictureKey) }
    }

    /// The picture to hide icons behind now: nil for the wallpaper, including
    /// when the chosen picture has since been moved or deleted.
    var hiddenIconsPictureInUse: URL? {
        guard let url = hiddenIconsPicture, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
