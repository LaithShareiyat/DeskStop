import AppKit
import DisplayCore
import SwiftUI

/// Shows `MenuPanelView` in a popover under the status item.
///
/// One popover and one hosting controller for the app's lifetime: the panel
/// keeps its open groups and measured page heights between openings, and the
/// model it observes is refreshed just before each one.
final class MenuPanelController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let model: AppModel
    private weak var button: NSStatusBarButton?
    /// When the popover last closed. A click on the status item while the panel
    /// is open closes it on mouse-down, then arrives as the button's action, which
    /// would reopen it; this tells the two apart.
    private var lastClosed = Date.distantPast
    /// An invisible, click-through window at the icon's position when the panel
    /// opened, which the popover hangs from. Over a full-screen app the menu bar
    /// slides away, and a popover attached to the status item slid with it.
    private var anchorWindow: NSPanel?

    init(model: AppModel, actions: UIActions) {
        self.model = model
        super.init()
        let root = MenuPanelView(model: model)
            .environment(\.uiActions, actions)
        let host = NSHostingController(rootView: root)
        // Follow the SwiftUI content: switching tabs or folding a group
        // resizes the popover rather than clipping or padding it.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    func toggle(from button: NSStatusBarButton) {
        if popover.isShown {
            close()
        } else if Date().timeIntervalSince(lastClosed) > 0.3 {
            show(from: button)
        }
    }

    func show(from button: NSStatusBarButton) {
        model.panelScreenHeight = button.window?.screen?.visibleFrame.height
        model.refresh()
        PermissionCenter.shared.refresh()
        popover.appearance = AppearanceMode.panelAppearance
        self.button = button
        // Activate first, so the popover becomes key: its keyboard shortcuts
        // work, and a click anywhere else closes it.
        NSApp.activate(ignoringOtherApps: true)
        let anchor = pinnedAnchorView(for: button) ?? button
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        // Without these it closes when another display is in full screen, and
        // stays on the Space it opened in.
        popover.contentViewController?.view.window?.collectionBehavior
            .insert([.fullScreenAuxiliary, .canJoinAllSpaces])
        if !PanelStyle.systemDrawsLiquidGlass {
            makeBackgroundSolid()
        }
        button.highlight(true)
    }

    /// Before Liquid Glass, a popover's background is a thin material that lets
    /// the wallpaper show through. The view drawing the balloon and arrow is an
    /// `NSVisualEffectView` (`NSPopoverFrame`); switching it to the
    /// window-background material, held inactive, makes it opaque without changing
    /// its shape. Set on every show as a cheap safeguard.
    private func makeBackgroundSolid() {
        var view = popover.contentViewController?.view.superview
        while let candidate = view, !(candidate is NSVisualEffectView) {
            view = candidate.superview
        }
        guard let frame = view as? NSVisualEffectView else { return }
        frame.material = .windowBackground
        frame.state = .inactive
    }

    func close() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    /// Stamped when closing starts, not when the animation ends: the
    /// mouse-up can land in between.
    func popoverWillClose(_ notification: Notification) {
        lastClosed = Date()
    }

    func popoverDidClose(_ notification: Notification) {
        // A walk-through doesn't pick up again the next time the panel opens.
        model.panelTour = nil
        button?.highlight(false)
        anchorWindow?.orderOut(nil)
        anchorWindow = nil
    }

    /// A view at the icon's position (`StatusItemAnchor`), in its own window
    /// that neither moves with the menu bar nor takes clicks.
    private func pinnedAnchorView(for button: NSStatusBarButton) -> NSView? {
        guard let buttonWindow = button.window else { return nil }
        let iconRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let rect = StatusItemAnchor.anchorRect(iconRect: iconRect,
                                               screenFrames: NSScreen.screens.map(\.frame))
        anchorWindow?.orderOut(nil)
        let window = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        window.contentView = view
        window.orderFrontRegardless()
        anchorWindow = window
        return view
    }
}
