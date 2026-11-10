import AppKit

/// Lists the apps a layout can save, and launches saved apps on restore.
enum RunningApps {
    struct Candidate {
        let app: SavedApp
        let icon: NSImage?
        let isRunning: Bool
    }

    /// Currently-running apps with a normal UI, excluding this app and Finder,
    /// sorted by name.
    static func candidates() -> [Candidate] {
        let ownID = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { running -> Candidate? in
                guard let bundleID = running.bundleIdentifier,
                      bundleID != ownID,
                      bundleID != "com.apple.finder" else { return nil }
                let name = running.localizedName ?? bundleID
                return Candidate(app: SavedApp(bundleIdentifier: bundleID, name: name),
                                 icon: running.icon, isRunning: true)
            }
            .sorted { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
    }

    /// Apps installed in the usual folders (one level of subfolders deep), minus
    /// background-only apps, this app and Finder, sorted by name.
    static func installed() -> [Candidate] {
        let fileManager = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities",
                     "/System/Applications", "/System/Applications/Utilities",
                     NSHomeDirectory() + "/Applications"]
        let skip = [Bundle.main.bundleIdentifier, "com.apple.finder"]
        var seen = Set<String>()
        var found: [Candidate] = []

        func add(_ url: URL) {
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                  !skip.contains(id), !seen.contains(id) else { return }
            let info = bundle.infoDictionary ?? [:]
            if info["LSUIElement"] as? Bool == true || info["LSBackgroundOnly"] as? Bool == true { return }
            seen.insert(id)
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            found.append(Candidate(app: SavedApp(bundleIdentifier: id, name: name),
                                   icon: icon, isRunning: false))
        }

        for root in roots {
            let entries = (try? fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])) ?? []
            for entry in entries {
                if entry.pathExtension == "app" {
                    add(entry)
                } else if let inner = try? fileManager.contentsOfDirectory(
                    at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    inner.filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        return found.sorted { $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending }
    }

    /// Launches each saved app that isn't already running. Never quits anything;
    /// opens without activating so focus stays on the restored desktop; skips
    /// uninstalled apps.
    static func launch(_ apps: [SavedApp]) {
        guard !apps.isEmpty else { return }
        let ws = NSWorkspace.shared
        let running = Set(ws.runningApplications.compactMap { $0.bundleIdentifier })
        for app in apps where !running.contains(app.bundleIdentifier) {
            guard let url = ws.urlForApplication(withBundleIdentifier: app.bundleIdentifier) else {
                NSLog("DeskStop: saved app not installed, skipping \(app.bundleIdentifier)")
                continue
            }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            ws.openApplication(at: url, configuration: config) { _, error in
                if let error = error {
                    NSLog("DeskStop: launch failed for \(app.bundleIdentifier): \(error)")
                }
            }
        }
    }
}
