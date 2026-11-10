import Foundation

/// The macOS wallpapers on this Mac that exist as full-size pictures, for
/// the hidden-icons picture gallery.
///
/// Some come with macOS; the rest are downloaded the first time they're
/// picked in System Settings › Wallpaper, and until then exist only as small
/// previews, too small to cover a screen. So the gallery lists what's here
/// and says the others arrive that way. Video wallpapers contribute their
/// still picture where macOS keeps one.
enum MacWallpapers {
    struct Item: Identifiable, Hashable {
        let url: URL
        /// The file's name without its extension, e.g. "Sonoma Horizon".
        let name: String
        var id: String { url.path }
    }

    private static let system = URL(fileURLWithPath: "/System/Library/Desktop Pictures", isDirectory: true)
    private static let downloaded = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.mobileAssetDesktop", isDirectory: true)
    private static let pictureExtensions: Set<String> = ["heic", "jpg", "jpeg", "png", "tif", "tiff"]

    /// Wallpapers that come with macOS or that it has downloaded, by name.
    static func pictures() -> [Item] {
        var urls = files(in: system) + files(in: downloaded)
        // Newer wallpapers keep a still beside their videos, a folder each.
        let stills = system.appendingPathComponent(".wallpapers", isDirectory: true)
        for folder in (try? FileManager.default.contentsOfDirectory(
            at: stills, includingPropertiesForKeys: nil)) ?? [] {
            urls += files(in: folder).filter { !$0.lastPathComponent.contains("Thumbnail") }
        }
        return items(urls)
    }

    /// The plain colours macOS offers as wallpapers.
    static func colours() -> [Item] {
        items(files(in: system.appendingPathComponent("Solid Colors", isDirectory: true)))
    }

    private static func files(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { pictureExtensions.contains($0.pathExtension.lowercased()) }
    }

    /// One item per name, sorted as Finder would.
    private static func items(_ urls: [URL]) -> [Item] {
        var seen = Set<String>()
        return urls
            .map { Item(url: $0, name: $0.deletingPathExtension().lastPathComponent) }
            .filter { seen.insert($0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
