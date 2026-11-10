import AppKit
import SwiftUI

/// The app's preferences window: a sidebar of pages, each a column of cards
/// (`SettingsView`).
///
/// Every control calls the same `AppDelegate` or `PresetActionsController`
/// method its menu item calls, through `UIActions` — no preference logic
/// lives here or in the view.
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private static var shared: SettingsWindow?

    private let model: AppModel
    private let router = SettingsRouter()

    /// Opens Settings, or brings the open window forward — never a second one.
    static func show(model: AppModel, actions: UIActions, page: SettingsPage? = nil,
                     layout: UUID? = nil) {
        if shared == nil {
            shared = SettingsWindow(model: model, actions: actions)
        }
        guard let shared else { return }
        if let page { shared.router.page = page }
        if let layout { shared.router.layout = layout }
        shared.reload()
        NSApp.activate(ignoringOtherApps: true)
        shared.showWindow(nil)
        shared.window?.makeKeyAndOrderFront(nil)
    }

    private init(model: AppModel, actions: UIActions) {
        self.model = model
        let root = SettingsView(model: model, router: router)
            .environment(\.uiActions, actions)
        let host = NSHostingController(rootView: root)
        // The window, not the page, owns its size: pages differ a lot in
        // height, and letting content drive the frame makes it jump on every
        // sidebar click.
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "DeskStop Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.defaultContentSize)
        window.contentMinSize = Self.minimumContentSize
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        // Applies the frame saved last time, enlarged to the current minimum: AppKit
        // doesn't hold a restored frame to it.
        windowFrameAutosaveName = "DeskStopSettings"
        if let content = window.contentView?.frame.size,
           content.width < Self.minimumContentSize.width || content.height < Self.minimumContentSize.height {
            window.setContentSize(NSSize(width: max(content.width, Self.defaultContentSize.width),
                                         height: max(content.height, Self.defaultContentSize.height)))
        }
        // The menu and this window can change the same switches, so
        // whichever surface the user looks at second must not be stale.
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Wide enough that the Layouts page's detail column, beside its list,
    /// keeps every row on its feet: at 760pt a row's title wrapped one
    /// letter per line and its buttons were crushed.
    static let defaultContentSize = NSSize(width: 860, height: 560)
    static let minimumContentSize = NSSize(width: 820, height: 480)

    @objc private func appDidBecomeActive() {
        guard window?.isVisible == true else { return }
        reload()
    }

    private func reload() {
        model.refresh()
        model.refreshNotificationWarning()
    }
}
