import Foundation

/// Where DeskStop keeps its data: layouts, shortcuts, schedules and the undo
/// slot, in `Application Support/DeskStop/`.
enum DataFolder {
    static let name = "DeskStop"

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name, isDirectory: true)
    }

    /// Creates the folder if needed and returns it.
    static func ensured() -> URL {
        let dir = url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
