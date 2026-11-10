import AppKit
import Carbon.HIToolbox

enum HotkeyFormatter {
    /// Render a chord as a user-readable string like "⌃⌥⌘R".
    static func display(_ chord: HotkeyChord) -> String {
        var s = ""
        if chord.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if chord.modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if chord.modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if chord.modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyName(for: chord.keyCode)
        return s
    }

    private static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            return characterForKeyCode(keyCode)?.uppercased() ?? "Key\(keyCode)"
        }
    }

    private static func characterForKeyCode(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutPtr, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let err = UCKeyTranslate(keyLayout,
                                 UInt16(keyCode),
                                 UInt16(kUCKeyActionDisplay),
                                 0,
                                 UInt32(LMGetKbdType()),
                                 OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                 &deadKeyState,
                                 chars.count,
                                 &length,
                                 &chars)
        guard err == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Modal panel that records a single global hotkey chord.
final class HotkeyRecorder {

    static func record(presetName: String,
                       existing: HotkeyChord?,
                       collision: @escaping (HotkeyChord) -> String?) -> HotkeyChord? {
        let view = RecorderView()
        view.presetName = presetName
        view.chord = existing
        view.collisionLookup = collision

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
                            styleMask: [.titled],
                            backing: .buffered,
                            defer: false)
        panel.title = "Record Shortcut"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = view
        view.refresh()
        // Size the panel to its layout's natural height so there's no empty
        // strip under the buttons. Width stays fixed at 400 for stability.
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        panel.setContentSize(NSSize(width: 400, height: fitting.height))

        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        let code = NSApp.runModal(for: panel)
        panel.orderOut(nil)

        return code == .OK ? view.chord : nil
    }
}

private final class RecorderView: NSView {
    var presetName: String = ""
    var chord: HotkeyChord?
    var collisionLookup: ((HotkeyChord) -> String?) = { _ in nil }

    private let promptLabel  = NSTextField(labelWithString: "")
    private let chordLabel   = NSTextField(labelWithString: "")
    private let helperLabel  = NSTextField(labelWithString: "")
    private let saveButton   = NSButton(title: "Save", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let clearButton  = NSButton(title: "Clear", target: nil, action: nil)
    private let chordBox     = NSBox()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    private func buildUI() {
        // Prompt — secondary, centered, sets the context.
        promptLabel.alignment = .center
        promptLabel.font = .systemFont(ofSize: 13)
        promptLabel.textColor = .secondaryLabelColor

        // Chord display — large, centered, in a subtle rounded box that
        // mirrors the System Settings shortcut field. The label lives in the
        // box's default contentView so NSBox handles its own insets.
        chordLabel.alignment = .center
        chordLabel.font = .systemFont(ofSize: 26, weight: .medium)
        chordLabel.textColor = .labelColor
        chordLabel.translatesAutoresizingMaskIntoConstraints = false

        chordBox.boxType = .custom
        // No `borderType` — it only applies to the deprecated NSBoxOldStyle. For a
        // .custom box the border comes from borderColor plus borderWidth
        // (NSBox defaults to 1.0), so setting it here was a no-op.
        chordBox.borderColor = .separatorColor
        chordBox.fillColor = .controlBackgroundColor
        chordBox.cornerRadius = 8
        chordBox.titlePosition = .noTitle
        chordBox.translatesAutoresizingMaskIntoConstraints = false

        if let boxContent = chordBox.contentView {
            boxContent.addSubview(chordLabel)
            NSLayoutConstraint.activate([
                chordLabel.centerXAnchor.constraint(equalTo: boxContent.centerXAnchor),
                chordLabel.centerYAnchor.constraint(equalTo: boxContent.centerYAnchor),
                chordLabel.leadingAnchor.constraint(greaterThanOrEqualTo: boxContent.leadingAnchor, constant: 12),
                chordLabel.trailingAnchor.constraint(lessThanOrEqualTo: boxContent.trailingAnchor, constant: -12),
            ])
        }
        NSLayoutConstraint.activate([
            chordBox.widthAnchor.constraint(equalToConstant: 240),
            chordBox.heightAnchor.constraint(equalToConstant: 50),
        ])

        // Helper text below the chord — collision warning, modifier hint, etc.
        helperLabel.alignment = .center
        helperLabel.font = .systemFont(ofSize: 11)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.maximumNumberOfLines = 2
        helperLabel.lineBreakMode = .byWordWrapping

        // Buttons — bezel matches macOS standard. Save is the default
        // (Return), Cancel binds Escape.
        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearChord)

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"

        saveButton.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"

        // Button row: Clear on the left, then a flexible spacer, then Cancel
        // and Save aligned to the trailing edge (HIG order for macOS).
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [clearButton, spacer, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12
        buttonRow.distribution = .fill

        // Outer vertical stack — `.centerX` alignment centers each child on
        // its intrinsic width. The button row and helper label are then
        // explicitly pinned to the stack's content width so they aren't
        // shrunk to their content's natural size.
        let stack = NSStackView(views: [promptLabel, chordBox, helperLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 24),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -24),
            helperLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -48),
        ])
    }

    func refresh() {
        promptLabel.stringValue = "Shortcut for \u{201C}\(presetName)\u{201D}"
        if let c = chord {
            chordLabel.stringValue = HotkeyFormatter.display(c)
            chordLabel.textColor = .labelColor
            if let other = collisionLookup(c) {
                helperLabel.stringValue = "Already used by \u{201C}\(other)\u{201D}"
                helperLabel.textColor = .systemRed
                saveButton.isEnabled = false
            } else if !hasModifier(c) {
                helperLabel.stringValue = "Include at least one of ⌃ ⌥ ⇧ ⌘"
                helperLabel.textColor = .systemOrange
                saveButton.isEnabled = false
            } else if modifierCount(c) < 2 {
                helperLabel.stringValue = "Tip: two modifier keys, such as ⌃⌥A, are less likely to clash"
                helperLabel.textColor = .secondaryLabelColor
                saveButton.isEnabled = true
            } else {
                helperLabel.stringValue = "Click Save, or type a different shortcut"
                helperLabel.textColor = .secondaryLabelColor
                saveButton.isEnabled = true
            }
            clearButton.isEnabled = true
        } else {
            chordLabel.stringValue = "Type a Shortcut"
            chordLabel.textColor = .tertiaryLabelColor
            helperLabel.stringValue = "Hold ⌃ ⌥ ⇧ or ⌘ and press a key"
            helperLabel.textColor = .secondaryLabelColor
            saveButton.isEnabled = false
            clearButton.isEnabled = false
        }
    }

    private func hasModifier(_ c: HotkeyChord) -> Bool {
        let mask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        return c.modifiers & mask != 0
    }

    private func modifierCount(_ c: HotkeyChord) -> Int {
        var count = 0
        if c.modifiers & UInt32(cmdKey)     != 0 { count += 1 }
        if c.modifiers & UInt32(optionKey)  != 0 { count += 1 }
        if c.modifiers & UInt32(controlKey) != 0 { count += 1 }
        if c.modifiers & UInt32(shiftKey)   != 0 { count += 1 }
        return count
    }

    override func keyDown(with event: NSEvent) {
        let kc = UInt32(event.keyCode)
        // Let Escape bubble up so the Cancel button's keyEquivalent picks it up.
        if Int(kc) == kVK_Escape { super.keyDown(with: event); return }
        let mods = carbonModifiers(from: event.modifierFlags)
        chord = HotkeyChord(keyCode: kc, modifiers: mods)
        refresh()
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command)  { m |= UInt32(cmdKey) }
        if flags.contains(.option)   { m |= UInt32(optionKey) }
        if flags.contains(.control)  { m |= UInt32(controlKey) }
        if flags.contains(.shift)    { m |= UInt32(shiftKey) }
        return m
    }

    @objc private func save()        { NSApp.stopModal(withCode: .OK) }
    @objc private func cancel()      { NSApp.stopModal(withCode: .cancel) }
    @objc private func clearChord()  { chord = nil; refresh() }
}
