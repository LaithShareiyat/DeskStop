import AppKit

/// Setup panel for restoring a layout from a Focus, styled like the other app
/// panels (centered prompt, rounded boxes, trailing default button). It also
/// generates a `deskstop://restore` link for a chosen layout with a Copy
/// button, for Raycast, Alfred and Shortcuts.
final class FocusSetupWindow: NSObject {
    private static var shared: FocusSetupWindow?

    private let panel: NSPanel
    private let presets: [Preset]
    private let presetPopup = NSPopUpButton()
    private let urlLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)

    static func show(presetStore: PresetStore) {
        // Rebuild each time so the preset list is current.
        shared = FocusSetupWindow(presets: presetStore.list())
        NSApp.activate(ignoringOtherApps: true)
        shared?.panel.center()
        shared?.panel.makeKeyAndOrderFront(nil)
    }

    private init(presets: [Preset]) {
        self.presets = presets
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
                        styleMask: [.titled, .closable],
                        backing: .buffered, defer: false)
        panel.title = "Restore with a Focus or a Link"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init()

        let view = buildView()
        panel.contentView = view
        view.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 480, height: view.fittingSize.height))
        updateURL()
    }

    private func buildView() -> NSView {
        let prompt = NSTextField(wrappingLabelWithString: Self.promptText)
        prompt.isSelectable = false
        prompt.alignment = .center
        prompt.font = .systemFont(ofSize: 12)
        prompt.textColor = .secondaryLabelColor
        prompt.preferredMaxLayoutWidth = 400

        let steps = Self.steps
        let stepStack = NSStackView(views: steps.enumerated().map { index, text in
            let number = NSTextField(labelWithString: "\(index + 1).")
            number.font = .systemFont(ofSize: 12, weight: .semibold)
            number.textColor = .secondaryLabelColor
            number.widthAnchor.constraint(equalToConstant: 18).isActive = true
            let body = NSTextField(wrappingLabelWithString: text)
            body.font = .systemFont(ofSize: 12)
            body.preferredMaxLayoutWidth = 360
            let row = NSStackView(views: [number, body])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 6
            // Optional per-step screenshot: bundle a Resources/focus-step-N.png
            // (copied into the app by build-app.sh) and it appears under the
            // step, indented to the text column. No image → text-only row.
            guard let art = Self.stepImage(index + 1) else { return row }
            let column = NSStackView(views: [row, art])
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 6
            return column
        })
        stepStack.orientation = .vertical
        stepStack.alignment = .leading
        stepStack.spacing = 8
        let stepsBox = Self.roundedBox(around: stepStack)

        // Preset → link row, in a second box.
        let presetLabel = NSTextField(labelWithString: "Link for")
        presetLabel.font = .systemFont(ofSize: 12)
        presetPopup.addItems(withTitles: presets.map { "\($0.name) (\($0.displaySetupName))" })
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)

        urlLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlLabel.textColor = .secondaryLabelColor
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.isSelectable = true

        copyButton.target = self
        copyButton.action = #selector(copyURL)
        copyButton.bezelStyle = .rounded

        let pickerRow = NSStackView(views: [presetLabel, presetPopup])
        pickerRow.orientation = .horizontal
        pickerRow.spacing = 8
        let urlRow = NSStackView(views: [urlLabel, copyButton])
        urlRow.orientation = .horizontal
        urlRow.spacing = 8
        urlLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let urlStack: NSStackView
        if presets.isEmpty {
            let empty = NSTextField(wrappingLabelWithString:
                "Create a layout first. Its URL appears here.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .tertiaryLabelColor
            urlStack = NSStackView(views: [empty])
        } else {
            let linkCaption = NSTextField(wrappingLabelWithString:
                "Or restore a layout from Raycast, Alfred or Shortcuts with this link:")
            linkCaption.font = .systemFont(ofSize: 12)
            linkCaption.textColor = .secondaryLabelColor
            linkCaption.preferredMaxLayoutWidth = 400
            urlStack = NSStackView(views: [linkCaption, pickerRow, urlRow])
        }
        urlStack.orientation = .vertical
        urlStack.alignment = .leading
        urlStack.spacing = 8
        let urlBox = Self.roundedBox(around: urlStack)

        // Trailing default button, like the other panels.
        let openFocus = NSButton(title: "Open Focus Settings",
                                     target: self, action: #selector(openFocusSettings))
        openFocus.bezelStyle = .rounded
        openFocus.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [spacer, openFocus])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        let stack = NSStackView(views: [prompt, stepsBox, urlBox, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stepsBox.widthAnchor.constraint(equalToConstant: 432),
            urlBox.widthAnchor.constraint(equalToConstant: 432),
            buttonRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 24),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -24),
        ])
        return container
    }

    private static let promptText =
        "Restore a layout when a Focus turns on. Set it up once in System Settings:"

    private static let steps = [
        "Open Focus settings and click the Focus you want, such as Work.",
        "Under Focus Filters, click Add Filter and choose DeskStop.",
        "Choose the layout to restore, then click Add.",
    ]

    /// Bundled screenshot for step `n` (`focus-step-N.png`), sized to the box
    /// width, or nil when not shipped.
    private static func stepImage(_ n: Int) -> NSImageView? {
        guard let path = Bundle.main.path(forResource: "focus-step-\(n)", ofType: "png"),
              let image = NSImage(contentsOfFile: path) else { return nil }
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        let maxWidth: CGFloat = 384
        let scale = min(1, maxWidth / max(image.size.width, 1))
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: image.size.width * scale),
            view.heightAnchor.constraint(equalToConstant: image.size.height * scale),
        ])
        return view
    }

    /// The app's standard rounded, bordered box around arbitrary content.
    private static func roundedBox(around content: NSStackView) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.cornerRadius = 8
        box.titlePosition = .noTitle
        box.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        if let bc = box.contentView {
            bc.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: bc.leadingAnchor, constant: 12),
                content.trailingAnchor.constraint(equalTo: bc.trailingAnchor, constant: -12),
                content.topAnchor.constraint(equalTo: bc.topAnchor, constant: 12),
                content.bottomAnchor.constraint(equalTo: bc.bottomAnchor, constant: -12),
            ])
        }
        return box
    }

    private func selectedURL() -> String? {
        guard !presets.isEmpty else { return nil }
        let index = max(0, presetPopup.indexOfSelectedItem)
        guard index < presets.count else { return nil }
        var components = URLComponents()
        components.scheme = "deskstop"
        components.host = "restore"
        components.queryItems = [URLQueryItem(name: "name", value: presets[index].name)]
        return components.string
    }

    private func updateURL() {
        urlLabel.stringValue = selectedURL() ?? ""
    }

    @objc private func presetChanged() {
        updateURL()
    }

    @objc private func copyURL() {
        guard let url = selectedURL() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        copyButton.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.title = "Copy"
        }
    }

    @objc private func openFocusSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
