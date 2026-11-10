import AppKit

/// Shared modal helpers for the lightweight prompts used by menu actions.
enum Alerts {
    static func show(title: String, info: String, style: NSAlert.Style = .informational) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = info
            alert.alertStyle = style
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    static func prompt(title: String, message: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = defaultValue
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { input.window?.makeFirstResponder(input) }
        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? input.stringValue : nil
    }
}

/// Target for the new-layout sheet's checkboxes, so Create can be disabled
/// while nothing is selected. `NSControl.target` is weak, so the caller keeps
/// this alive for as long as the sheet is up.
private final class NewPresetAccessory: NSObject {
    let iconsBox = NSButton(checkboxWithTitle: "Restore icon positions",
                            target: nil, action: nil)
    let arrangementBox = NSButton(checkboxWithTitle: "Restore display arrangement",
                                  target: nil, action: nil)
    let modesBox = NSButton(checkboxWithTitle: "Restore resolution and refresh rate",
                            target: nil, action: nil)
    let appsBox = NSButton(checkboxWithTitle: "Open saved apps",
                           target: nil, action: nil)
    let hint = NSTextField(labelWithString: "")
    weak var createButton: NSButton?

    /// With every box unticked a save would do nothing, so Create is blocked.
    @objc func selectionChanged() {
        let any = iconsBox.state == .on
            || arrangementBox.state == .on
            || modesBox.state == .on
            || appsBox.state == .on
        createButton?.isEnabled = any
        hint.stringValue = any ? "" : "Choose at least one."
    }
}

extension Alerts {

    /// What the user asked a new desktop configuration to contain.
    struct NewPresetChoice {
        let name: String
        /// Whether restoring should put the icons back.
        let restoreIcons: Bool
        /// Whether restoring should also put the displays back.
        let restoreArrangement: Bool
        /// Whether restoring should also set each display's resolution,
        /// scaling and refresh rate back.
        let restoreModes: Bool
        /// Whether to follow up with the app picker. Everything is always
        /// captured; apps have to be chosen, so this only means "ask me next".
        let includeApps: Bool
    }

    /// Name a new layout and choose what it contains.
    ///
    /// Same `NSAlert` + `accessoryView` shape as `prompt`, with four opt-ins and a
    /// subtitle under each: "icon positions" and "display arrangement" are one
    /// word apart, and the subtitle tells desktop icons from physical monitors.
    /// The labels match the submenu toggles they map to. Laid out with explicit
    /// frames: `NSAlert` sizes its accessory from the view's frame, and an
    /// auto-layout container without constraints collapses.
    static func promptNewPreset(categoryLabel: String,
                                defaultName: String) -> NewPresetChoice? {
        let alert = NSAlert()
        alert.messageText = "New Layout"
        alert.informativeText =
            "Saves your desktop as it is now, for \(categoryLabel). "
            + "When this layout is restored:"

        let width: CGFloat = 340
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 199))
        let wiring = NewPresetAccessory()

        let input = NSTextField(frame: NSRect(x: 0, y: 175, width: width, height: 24))
        input.stringValue = defaultName
        accessory.addSubview(input)

        // Subtitles are indented to sit under the checkbox's title rather than
        // its glyph.
        func place(_ box: NSButton, _ subtitle: String,
                   boxY: CGFloat, subtitleY: CGFloat) {
            box.frame = NSRect(x: 0, y: boxY, width: width, height: 18)
            box.target = wiring
            box.action = #selector(NewPresetAccessory.selectionChanged)
            accessory.addSubview(box)

            let label = NSTextField(labelWithString: subtitle)
            label.frame = NSRect(x: 20, y: subtitleY, width: width - 20, height: 14)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            accessory.addSubview(label)
        }

        // Icons and the display arrangement default on; resolution and apps default
        // off, since both are felt more than a moved icon and should be asked for.
        wiring.iconsBox.state = .on
        wiring.arrangementBox.state = .on
        wiring.modesBox.state = .off
        wiring.appsBox.state = .off

        place(wiring.iconsBox,
              "Puts every icon back where it is now",
              boxY: 149, subtitleY: 133)
        place(wiring.arrangementBox,
              "Where each display sits and which is main",
              boxY: 111, subtitleY: 95)
        place(wiring.modesBox,
              "Each display's resolution, scaling and refresh rate",
              boxY: 73, subtitleY: 57)
        place(wiring.appsBox,
              "Opens apps you choose next",
              boxY: 35, subtitleY: 19)

        wiring.hint.frame = NSRect(x: 0, y: 0, width: width, height: 16)
        wiring.hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        wiring.hint.textColor = .systemRed
        accessory.addSubview(wiring.hint)

        alert.accessoryView = accessory
        wiring.createButton = alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        wiring.selectionChanged()

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { input.window?.makeFirstResponder(input) }

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return NewPresetChoice(name: input.stringValue,
                               restoreIcons: wiring.iconsBox.state == .on,
                               restoreArrangement: wiring.arrangementBox.state == .on,
                               restoreModes: wiring.modesBox.state == .on,
                               includeApps: wiring.appsBox.state == .on)
    }
}
