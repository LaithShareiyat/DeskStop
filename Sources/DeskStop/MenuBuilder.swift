import AppKit
import ServiceManagement

/// Builds the status-item menu. Pure construction: reads current state from
/// the stores and wires every item to one of two targets — the AppDelegate
/// for app-level toggles/windows, or the PresetActionsController for
/// per-preset operations.
final class MenuBuilder {
    private let presetStore: PresetStore
    private let hotkeyConfig: HotkeyConfigStore
    private let defaults: DefaultPresetStore
    private let displayMonitor: DisplayMonitor
    private let scheduler: Scheduler
    private let undoStore: UndoSlotStore
    /// Whether presentation mode currently hides the desktop.
    private let isDesktopHidden: () -> Bool
    private weak var appTarget: AppDelegate?
    private weak var presetTarget: PresetActionsController?

    init(presetStore: PresetStore,
         hotkeyConfig: HotkeyConfigStore,
         defaults: DefaultPresetStore,
         displayMonitor: DisplayMonitor,
         scheduler: Scheduler,
         undoStore: UndoSlotStore,
         isDesktopHidden: @escaping () -> Bool,
         appTarget: AppDelegate,
         presetTarget: PresetActionsController) {
        self.presetStore = presetStore
        self.hotkeyConfig = hotkeyConfig
        self.defaults = defaults
        self.displayMonitor = displayMonitor
        self.scheduler = scheduler
        self.undoStore = undoStore
        self.isDesktopHidden = isDesktopHidden
        self.appTarget = appTarget
        self.presetTarget = presetTarget
    }

    // MARK: - Build

    /// The right-click menu is a quick menu: restore a layout, make a new one,
    /// undo, hide icons, Settings, Quit. Everything that edits a layout lives
    /// in Settings → Layouts, so there is one place to change one.
    func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        let currentConfig = displayMonitor.currentConfiguration

        // Header: the display setup in use.
        let modeTitle = "Display Setup: \(currentConfig.displayName)"
        let modeItem = NSMenuItem(title: modeTitle, action: nil, keyEquivalent: "")
        modeItem.image = Self.menuIcon(currentConfig.displaySymbol)
        modeItem.isEnabled = false
        menu.addItem(modeItem)
        menu.addItem(.separator())

        let newItem = NSMenuItem(title: "New Layout",
                                 action: #selector(PresetActionsController.newPreset),
                                 keyEquivalent: "n")
        newItem.image = Self.menuIcon("plus")
        newItem.target = presetTarget
        menu.addItem(newItem)

        // Offered only while the display setup the snapshot was taken on is
        // still active — undoing onto different screens would misplace icons.
        if let snap = undoStore.load(), snap.categoryKey == currentConfig.key {
            let undoItem = NSMenuItem(title: "Undo Last Restore",
                                      action: #selector(PresetActionsController.undoLastRestore),
                                      keyEquivalent: "")
            undoItem.image = Self.menuIcon("arrow.uturn.backward")
            undoItem.target = presetTarget
            menu.addItem(undoItem)
        }

        appendPresetGroups(to: menu, currentCategoryKey: currentConfig.key)

        menu.addItem(.separator())
        let hideChord = UserDefaults.standard.hideDesktopHotkey
        let hideTitle = hideChord.map { "Hide Desktop Icons    \(HotkeyFormatter.display($0))" }
            ?? "Hide Desktop Icons"
        let hide = NSMenuItem(title: hideTitle,
                              action: #selector(AppDelegate.toggleHideDesktop), keyEquivalent: "")
        hide.state = isDesktopHidden() ? .on : .off
        hide.image = Self.menuIcon("eye.slash")
        hide.target = appTarget
        menu.addItem(hide)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings",
                                      action: #selector(AppDelegate.openSettings),
                                      keyEquivalent: ",")
        settingsItem.image = Self.menuIcon("gearshape")
        settingsItem.target = appTarget
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DeskStop",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
    }

    // MARK: - Layout sections

    private func appendPresetGroups(to menu: NSMenu, currentCategoryKey: String) {
        let groups = presetStore.presetsByCategory()
        guard !groups.isEmpty else { return }
        menu.addItem(.separator())

        // Current display setup first, then the rest (already sorted).
        if let current = groups.first(where: { $0.key == currentCategoryKey }) {
            appendCategorySection(to: menu, label: current.label, presets: current.presets)
        }
        for group in groups where group.key != currentCategoryKey {
            menu.addItem(.separator())
            appendCategorySection(to: menu, label: group.label, presets: group.presets)
        }
    }

    private func appendCategorySection(to menu: NSMenu,
                                       label: String,
                                       presets: [Preset]) {
        // Disabled header naming the display setup the layouts below belong to.
        let header = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: label.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(header)

        for preset in presets {
            menu.addItem(restoreItem(for: preset))
        }
    }

    /// One layout: choosing it restores it. A star marks the layout used for
    /// auto-restore; its shortcut, if any, follows the name.
    private func restoreItem(for preset: Preset) -> NSMenuItem {
        let chord = hotkeyConfig.chord(forPresetID: preset.id)
        let isDefault = defaults.isDefault(presetID: preset.id, forCategory: preset.categoryKey)

        let title = NSMutableAttributedString(string: preset.name,
                                              attributes: [.font: NSFont.menuFont(ofSize: 0)])
        if let c = chord {
            title.append(NSAttributedString(string: "    \(HotkeyFormatter.display(c))",
                                            attributes: [
                                                .font: NSFont.menuFont(ofSize: 0),
                                                .foregroundColor: NSColor.secondaryLabelColor
                                            ]))
        }
        let item = NSMenuItem(title: preset.name,
                              action: #selector(PresetActionsController.restorePreset(_:)),
                              keyEquivalent: "")
        item.attributedTitle = title
        item.image = isDefault ? Self.menuIcon("star.fill") : Self.blankMenuIcon()
        item.representedObject = preset.id.uuidString
        item.target = presetTarget
        return item
    }

    // MARK: - Icons & formatting

    /// Uniform icon column width so every menu item's icon — and the title that
    /// follows it — lines up vertically regardless of the symbol's own width.
    private static let menuIconSize = NSSize(width: 18, height: 16)

    /// Rendered menu icons are immutable and reused across every rebuild, so
    /// cache them — a rebuild otherwise re-renders ~10 + 8-per-preset images.
    private static var iconCache: [String: NSImage] = [:]

    private static func menuIcon(_ name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) else { return nil }
        let rendered = paddedToIconColumn(symbol)
        iconCache[name] = rendered
        return rendered
    }

    /// Draws a symbol centered inside a fixed-size canvas so all menu icons
    /// occupy the same horizontal space and their titles align. Template icons
    /// are tinted to the menu text color; non-template icons keep their color.
    private static func paddedToIconColumn(_ symbol: NSImage, template: Bool = true) -> NSImage {
        let canvas = NSImage(size: menuIconSize)
        canvas.lockFocus()
        let x = ((menuIconSize.width - symbol.size.width) / 2).rounded()
        let y = ((menuIconSize.height - symbol.size.height) / 2).rounded()
        symbol.draw(in: NSRect(x: x, y: y, width: symbol.size.width, height: symbol.size.height),
                    from: .zero, operation: .sourceOver, fraction: 1.0)
        canvas.unlockFocus()
        canvas.isTemplate = template
        return canvas
    }

    /// Transparent placeholder the same width as a menu icon, so items without
    /// an icon keep their titles aligned with their iconed siblings.
    private static func blankMenuIcon() -> NSImage {
        let img = NSImage(size: menuIconSize)
        img.isTemplate = true
        return img
    }
}
