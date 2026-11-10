import AppKit
import SchedulingCore

final class SchedulesWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private static var shared: SchedulesWindow?

    private let scheduleStore: ScheduleStore
    private let presetStore: PresetStore
    private var schedules: [Schedule] = []
    private let tableView = NSTableView()
    /// Shown over the table while there are no schedules.
    private let emptyLabel = NSTextField(labelWithString: "No schedules yet.\nClick Add to restore a layout at set times.")

    static func show(scheduleStore: ScheduleStore, presetStore: PresetStore) {
        if shared == nil {
            shared = SchedulesWindow(scheduleStore: scheduleStore, presetStore: presetStore)
        }
        NSApp.activate(ignoringOtherApps: true)
        shared?.reload()
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }

    init(scheduleStore: ScheduleStore, presetStore: PresetStore) {
        self.scheduleStore = scheduleStore
        self.presetStore = presetStore
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Schedules"
        window.center()
        super.init(window: window)
        buildUI()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload),
            name: ScheduleStore.didChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.documentView = tableView

        let nameCol = NSTableColumn(identifier: .init("name"))
        nameCol.title = "Name"; nameCol.width = 130
        let summaryCol = NSTableColumn(identifier: .init("summary"))
        summaryCol.title = "When"; summaryCol.width = 180
        let presetCol = NSTableColumn(identifier: .init("preset"))
        presetCol.title = "Layout"; presetCol.width = 130
        let onCol = NSTableColumn(identifier: .init("enabled"))
        onCol.title = "On"; onCol.width = 40
        [nameCol, summaryCol, presetCol, onCol].forEach { tableView.addTableColumn($0) }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.doubleAction = #selector(editSchedule)
        tableView.target = self

        let addButton = NSButton(title: "Add", target: self, action: #selector(addSchedule))
        let editButton = NSButton(title: "Edit", target: self, action: #selector(editSchedule))
        let deleteButton = NSButton(title: "Delete", target: self, action: #selector(deleteSchedule))
        let buttons = NSStackView(views: [addButton, editButton, deleteButton])
        buttons.orientation = .horizontal
        buttons.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(buttons)
        content.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    @objc private func reload() {
        schedules = scheduleStore.load()
        tableView.reloadData()
        emptyLabel.isHidden = !schedules.isEmpty
    }

    private func presetName(for id: UUID) -> String {
        presetStore.find(id: id)?.name ?? "(deleted layout)"
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { schedules.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let s = schedules[row]
        let id = tableColumn?.identifier.rawValue ?? ""
        if id == "enabled" {
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            check.state = s.enabled ? .on : .off
            return check
        }
        let text: String
        switch id {
        case "name": text = s.name
        case "summary": text = s.recurrence.summary()
        case "preset": text = presetName(for: s.presetID)
        default: text = ""
        }
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = tableView.row(for: sender)
        guard row >= 0, row < schedules.count else { return }
        scheduleStore.setEnabled(id: schedules[row].id, sender.state == .on)
    }

    // MARK: Actions

    @objc private func addSchedule() {
        ScheduleEditor.present(over: window, presetStore: presetStore, existing: nil) { [weak self] new in
            self?.scheduleStore.add(new)
        }
    }

    @objc private func editSchedule() {
        let row = tableView.selectedRow
        guard row >= 0, row < schedules.count else { return }
        ScheduleEditor.present(over: window, presetStore: presetStore, existing: schedules[row]) { [weak self] updated in
            self?.scheduleStore.update(updated)
        }
    }

    @objc private func deleteSchedule() {
        let row = tableView.selectedRow
        guard row >= 0, row < schedules.count else { return }
        scheduleStore.delete(id: schedules[row].id)
    }
}
