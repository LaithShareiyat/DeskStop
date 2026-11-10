import AppKit

/// Modal checklist of apps: the ones open now, then every installed app, with
/// a search field. Returns the ticked apps, or nil on Cancel.
/// A titled, non-closable NSPanel run with NSApp.runModal, like HotkeyRecorder;
/// it stays visible if the user Cmd-Tabs to check what's open.
final class AppPickerWindow: NSObject, NSSearchFieldDelegate {
    private struct Row {
        let check: NSButton
        let app: SavedApp
        let view: NSView
        let isRunning: Bool
    }

    private let panel: NSPanel
    private var rows: [Row] = []
    private var result: [SavedApp]?
    private let searchField = NSSearchField()
    private let openHeader = AppPickerWindow.sectionHeader("Open now")
    private let allHeader = AppPickerWindow.sectionHeader("All apps")
    private let emptyLabel = AppPickerWindow.sectionHeader("No apps match.")
    private static let notInstalled = " (not installed)"

    /// `preselected` is the layout's current apps; with none, the open apps
    /// start ticked.
    static func pick(preselected: [SavedApp] = []) -> [SavedApp]? {
        let running = RunningApps.candidates()
        let runningIDs = Set(running.map(\.app.bundleIdentifier))
        var others = RunningApps.installed().filter { !runningIDs.contains($0.app.bundleIdentifier) }
        // A saved app that is no longer installed stays listed, so it can be dropped.
        let known = runningIDs.union(others.map(\.app.bundleIdentifier))
        for app in preselected where !known.contains(app.bundleIdentifier) {
            others.insert(RunningApps.Candidate(
                app: SavedApp(bundleIdentifier: app.bundleIdentifier, name: app.name + Self.notInstalled),
                icon: nil, isRunning: false), at: 0)
        }
        let ticked = preselected.isEmpty ? runningIDs : Set(preselected.map(\.bundleIdentifier))

        let picker = AppPickerWindow(candidates: running + others, ticked: ticked)
        NSApp.activate(ignoringOtherApps: true)
        picker.panel.center()
        let code = NSApp.runModal(for: picker.panel)
        picker.panel.orderOut(nil)
        return code == .OK ? picker.result : nil
    }

    private init(candidates: [RunningApps.Candidate], ticked: Set<String>) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                        styleMask: [.titled],
                        backing: .buffered, defer: false)
        panel.title = "Choose Apps"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        super.init()
        let view = buildView(candidates, ticked: ticked)
        panel.contentView = view
        view.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 360, height: view.fittingSize.height))
        panel.initialFirstResponder = searchField
    }

    private static func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeRow(_ candidate: RunningApps.Candidate, ticked: Set<String>) -> NSView {
        let iconView = NSImageView()
        iconView.image = candidate.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
        ])
        let check = NSButton(checkboxWithTitle: candidate.app.name, target: nil, action: nil)
        check.state = ticked.contains(candidate.app.bundleIdentifier) ? .on : .off
        let row = NSStackView(views: [iconView, check])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        rows.append(Row(check: check, app: candidate.app, view: row, isRunning: candidate.isRunning))
        return row
    }

    private func buildView(_ candidates: [RunningApps.Candidate], ticked: Set<String>) -> NSView {
        // Centered prompt — matches the recorder / settings / onboarding windows.
        let prompt = NSTextField(wrappingLabelWithString: "Choose the apps to save with this layout. They open when it's restored.")
        prompt.isSelectable = false
        prompt.alignment = .center
        prompt.font = .systemFont(ofSize: 12)
        prompt.textColor = .secondaryLabelColor
        prompt.preferredMaxLayoutWidth = 300

        searchField.placeholderString = "Search apps"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // Checklist rows (naturally left-aligned inside the box).
        let listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.addArrangedSubview(openHeader)
        for candidate in candidates where candidate.isRunning {
            listStack.addArrangedSubview(makeRow(candidate, ticked: ticked))
        }
        listStack.addArrangedSubview(allHeader)
        for candidate in candidates where !candidate.isRunning {
            listStack.addArrangedSubview(makeRow(candidate, ticked: ticked))
        }
        listStack.addArrangedSubview(emptyLabel)
        filterChanged()

        // Flipped document view so a short list grows from the TOP (a normal,
        // non-flipped scroll view bottom-aligns short content).
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(listStack)
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: doc.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        // Rounded, bordered box around the list — the app's standard motif
        // (mirrors the hotkey recorder's chord box and the settings window).
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.cornerRadius = 8
        box.titlePosition = .noTitle
        box.translatesAutoresizingMaskIntoConstraints = false
        if let bc = box.contentView {
            bc.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: bc.leadingAnchor, constant: 10),
                scroll.trailingAnchor.constraint(equalTo: bc.trailingAnchor, constant: -10),
                scroll.topAnchor.constraint(equalTo: bc.topAnchor, constant: 10),
                scroll.bottomAnchor.constraint(equalTo: bc.bottomAnchor, constant: -10),
            ])
        }
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 312),
            box.heightAnchor.constraint(equalToConstant: 280),
            searchField.widthAnchor.constraint(equalToConstant: 312),
        ])

        // Buttons trailing — Cancel then Save (default), like the rest of the app.
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [spacer, cancel, save])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 12

        let stack = NSStackView(views: [prompt, searchField, box, buttonRow])
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
            container.widthAnchor.constraint(equalToConstant: 360),
            buttonRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 24),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -24),
            prompt.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
        return container
    }

    /// Hides rows that don't match the search, and any section left empty.
    private func filterChanged() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        var anyOpen = false, anyOther = false
        for row in rows {
            let matches = query.isEmpty
                || row.app.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            row.view.isHidden = !matches
            if matches { if row.isRunning { anyOpen = true } else { anyOther = true } }
        }
        openHeader.isHidden = !anyOpen
        allHeader.isHidden = !anyOther
        emptyLabel.isHidden = anyOpen || anyOther
    }

    func controlTextDidChange(_ obj: Notification) { filterChanged() }

    @objc private func save() {
        result = rows.filter { $0.check.state == .on }.map { row in
            var app = row.app
            if app.name.hasSuffix(Self.notInstalled) { app.name.removeLast(Self.notInstalled.count) }
            return app
        }
        NSApp.stopModal(withCode: .OK)
    }
    @objc private func cancel() { NSApp.stopModal(withCode: .cancel) }
}

/// Flipped view used as a scroll view's document so content top-aligns.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
