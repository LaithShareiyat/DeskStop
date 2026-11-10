import AppKit
import ServiceManagement
import UserNotifications

/// Settings → About → Uninstall: removes DeskStop and everything it stored
/// on this Mac, moves the app to the Trash, and exits.
///
/// Removed: the configurations, hotkeys, schedules and undo slot (the
/// `DeskStop` data folder), every preference, DeskStop's permission
/// answers, its login item, delivered notifications, caches and saved state.
///
/// Desktop icons are never moved: they stay wherever they are now.
enum SelfUninstaller {
    /// The confirmation's explanation, kept beside the code that does it.
    static let summary = """
        This deletes all your layouts, schedules, shortcuts and settings, \
        removes DeskStop's permissions and login item, and moves it to the \
        Trash. Your desktop icons stay where they are.
        """

    /// Removes everything and exits. Never returns.
    static func run() -> Never {
        var problems: [String] = []
        let bundleID = Bundle.main.bundleIdentifier
        let fileManager = FileManager.default
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]

        // A login item left registered points at an app that is gone.
        if SMAppService.mainApp.status == .enabled {
            do { try SMAppService.mainApp.unregister() } catch {
                problems.append("Couldn't remove the login item: \(error.localizedDescription)")
            }
        }

        if bundleID != nil {
            let center = UNUserNotificationCenter.current()
            center.removeAllDeliveredNotifications()
            center.removeAllPendingNotificationRequests()
        }

        if !Permissions.resetPrivacyAnswers(service: "All") {
            problems.append("Couldn't reset DeskStop's permissions. Remove it from System Settings → Privacy & Security yourself.")
        }

        var folders = [library.appendingPathComponent("Application Support/\(DataFolder.name)")]
        if let bundleID {
            folders += [library.appendingPathComponent("Caches/\(bundleID)"),
                        library.appendingPathComponent("HTTPStorages/\(bundleID)"),
                        library.appendingPathComponent("Saved Application State/\(bundleID).savedState")]
        }
        for folder in folders where fileManager.fileExists(atPath: folder.path) {
            do { try fileManager.removeItem(at: folder) } catch {
                problems.append("Couldn't remove \(folder.path): \(error.localizedDescription)")
            }
        }

        // Last of the data, because anything above may still have written a
        // preference. Nothing after this runs AppKit's own shutdown, which
        // would write some back.
        if let bundleID {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        // Moving a running app is safe: the process keeps the files it has
        // open. Only a real bundle goes to the Trash, never a build folder.
        let app = Bundle.main.bundleURL
        if app.pathExtension == "app" {
            do { try fileManager.trashItem(at: app, resultingItemURL: nil) } catch {
                problems.append("Couldn't move \(app.lastPathComponent) to the Trash: "
                                + "\(error.localizedDescription). Drag it there yourself.")
            }
        }

        if !problems.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "DeskStop was mostly removed"
            alert.informativeText = problems.joined(separator: "\n\n")
            alert.addButton(withTitle: "Quit")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        exit(0)
    }
}
