import Foundation

/// Parses and executes `deskstop://` automation URLs. Restore runs
/// through the same injected path as a hotkey press (Finder guards, app
/// launching, alerts all included); icon commands map onto the
/// presentation-mode toggle.
struct URLCommandHandler {
    static let supportedCommandsHelp = """
    deskstop://restore?name=<layout>  (or ?id=<uuid>)
    deskstop://hide-icons
    deskstop://show-icons
    deskstop://toggle-icons
    deskstop://settings  (or ?page=layouts, shortcuts, ...)
    """

    let presetStore: PresetStore
    let displayMonitor: DisplayMonitor
    let restore: (UUID) -> Void
    let hideIcons: () -> Void
    let showIcons: () -> Void
    let toggleIcons: () -> Void
    /// nil opens Settings on the page it was last on.
    let openSettings: (SettingsPage?) -> Void

    func handle(_ url: URL) {
        guard url.scheme?.lowercased() == "deskstop" else { return }
        switch url.host?.lowercased() {
        case "restore":
            handleRestore(url)
        case "hide-icons":
            hideIcons()
        case "show-icons":
            showIcons()
        case "toggle-icons":
            toggleIcons()
        case "settings":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let name = items.first(where: { $0.name.lowercased() == "page" })?.value else {
                openSettings(nil)
                return
            }
            guard let page = SettingsPage(rawValue: name.lowercased()) else {
                let pages = SettingsPage.allCases.map(\.rawValue).joined(separator: ", ")
                Alerts.show(title: "Settings page not found",
                            info: "There is no Settings page called \(name).\n\nThe pages are: \(pages).",
                            style: .warning)
                return
            }
            openSettings(page)
        default:
            Alerts.show(title: "Unknown DeskStop link",
                        info: "\(url.absoluteString)\n\nDeskStop understands:\n\(Self.supportedCommandsHelp)",
                        style: .warning)
        }
    }

    private func handleRestore(_ url: URL) {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }

        if let idString = value("id") {
            guard let id = UUID(uuidString: idString), presetStore.find(id: id) != nil else {
                Alerts.show(title: "Layout not found",
                            info: "No layout has the id \(idString).",
                            style: .warning)
                return
            }
            restore(id)
            return
        }

        guard let name = value("name"), !name.isEmpty else {
            Alerts.show(title: "Layout name missing",
                        info: "DeskStop understands:\n\(Self.supportedCommandsHelp)",
                        style: .warning)
            return
        }

        let matches = presetStore.list().filter {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        let currentKey = displayMonitor.currentConfiguration.key
        if let current = matches.first(where: { $0.categoryKey == currentKey }) {
            // A preset for the display setup we're on always wins.
            restore(current.id)
        } else if matches.count == 1 {
            restore(matches[0].id)
        } else if matches.isEmpty {
            Alerts.show(title: "Layout not found",
                        info: "No layout is called \u{201C}\(name)\u{201D}.",
                        style: .warning)
        } else {
            let byID = matches
                .map { "\u{2022} \($0.displaySetupName):\ndeskstop://restore?id=\($0.id.uuidString)" }
                .joined(separator: "\n")
            Alerts.show(title: "More than one layout has that name",
                        info: "\u{201C}\(name)\u{201D} exists for \(matches.count) display setups, none of them the current one. Use one of these links instead:\n\n\(byID)",
                        style: .warning)
        }
    }
}
