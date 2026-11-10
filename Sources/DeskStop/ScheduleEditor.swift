import AppKit
import SwiftUI
import SchedulingCore

/// The editor for one schedule, shown as a sheet on the Schedules window.
///
/// Days are picked visually: a week strip of day tiles for Weekly, a month
/// grid for Dates. A SwiftUI sheet rather than an `NSAlert`, so it can resize
/// with the pattern chosen.
enum ScheduleEditor {
    static func present(over parent: NSWindow?,
                        presetStore: PresetStore,
                        existing: Schedule?,
                        onSave: @escaping (Schedule) -> Void) {
        let presets = presetStore.list()
        guard !presets.isEmpty else {
            Alerts.show(title: "No layouts yet",
                        info: "Create a layout first, then you can schedule it.")
            return
        }

        let model = ScheduleEditorModel(presets: presets, existing: existing)
        let sheet = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        sheet.title = existing == nil ? "New Schedule" : "Edit Schedule"

        func close() {
            if let parent, sheet.sheetParent == parent {
                parent.endSheet(sheet)
            } else {
                NSApp.stopModal()
                sheet.orderOut(nil)
            }
            // The view's closures hold the sheet; dropping the view frees both.
            DispatchQueue.main.async { sheet.contentViewController = nil }
        }
        let view = ScheduleEditorView(
            model: model,
            title: sheet.title,
            onCancel: { close() },
            onSave: {
                guard let schedule = model.build() else { return }
                close()
                onSave(schedule)
            })
        let host = NSHostingController(rootView: view)
        // The sheet takes the view's ideal size, so switching between Weekly
        // and Dates resizes it to fit.
        host.sizingOptions = [.preferredContentSize]
        sheet.contentViewController = host

        NSApp.activate(ignoringOtherApps: true)
        if let parent {
            parent.beginSheet(sheet)
        } else {
            sheet.center()
            NSApp.runModal(for: sheet)
        }
    }
}

// MARK: - Model

final class ScheduleEditorModel: ObservableObject {
    enum Pattern: String, CaseIterable, Identifiable {
        case weekly = "Weekly", dates = "Dates"
        var id: String { rawValue }
    }

    @Published var name: String
    @Published var presetIndex: Int
    @Published var pattern: Pattern
    @Published var weekdays: Set<Weekday>
    @Published var dates: [CalendarDate]
    @Published var timesText: String
    /// The first day of the month the date grid shows.
    @Published var month: Date

    let presets: [Preset]
    private let existingID: UUID?
    /// Editing must not flip a disabled schedule back on; new ones start on.
    private let existingEnabled: Bool

    /// Weeks start on Monday in the strip and the grid.
    let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    init(presets: [Preset], existing: Schedule?) {
        self.presets = presets
        existingID = existing?.id
        existingEnabled = existing?.enabled ?? true
        name = existing?.name ?? ""
        presetIndex = existing.flatMap { e in presets.firstIndex { $0.id == e.presetID } } ?? 0
        pattern = .weekly
        weekdays = [.monday, .tuesday, .wednesday, .thursday, .friday]
        dates = []
        timesText = "09:00"
        month = Date()

        switch existing?.recurrence {
        case let .weekly(days, times)?:
            weekdays = days
            timesText = Self.format(times)
        case let .dates(days, times)?:
            pattern = .dates
            dates = days.sorted(by: Self.ascending)
            timesText = Self.format(times)
        case .unknown?, nil:
            break
        }
        // Open the grid on the first chosen date, or this month.
        let shown = dates.first.flatMap { calendar.date(from: DateComponents(year: $0.year, month: $0.month)) } ?? Date()
        month = calendar.dateInterval(of: .month, for: shown)?.start ?? shown
    }

    // MARK: Parsing

    var times: [TimeOfDay] {
        timesText.split(separator: ",").compactMap { part in
            let comps = part.trimmingCharacters(in: .whitespaces).split(separator: ":")
            guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]),
                  (0...23).contains(h), (0...59).contains(m) else { return nil }
            return TimeOfDay(hour: h, minute: m)
        }
    }

    /// Every comma-separated part is a valid time.
    private var timesAreValid: Bool {
        let parts = timesText.split(separator: ",").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return !parts.isEmpty && parts.count == times.count
    }

    /// What's missing, in a sentence, or nil when the schedule can be saved.
    var problem: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the schedule a name." }
        switch pattern {
        case .weekly:
            if weekdays.isEmpty { return "Choose at least one day." }
            if !timesAreValid { return "Enter times as HH:MM, separated by commas." }
        case .dates:
            if dates.isEmpty { return "Choose at least one date." }
            if !timesAreValid { return "Enter times as HH:MM, separated by commas." }
        }
        return nil
    }

    func build() -> Schedule? {
        guard problem == nil, presets.indices.contains(presetIndex) else { return nil }
        let recurrence: Recurrence
        switch pattern {
        case .weekly: recurrence = .weekly(days: weekdays, times: times)
        case .dates: recurrence = .dates(days: dates.sorted(by: Self.ascending), times: times)
        }
        return Schedule(id: existingID ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespaces),
                        presetID: presets[presetIndex].id,
                        enabled: existingEnabled,
                        recurrence: recurrence)
    }

    // MARK: Days

    func toggle(_ day: Weekday) {
        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
    }

    func toggle(_ date: CalendarDate) {
        if let index = dates.firstIndex(of: date) { dates.remove(at: index) } else { dates.append(date) }
        dates.sort(by: Self.ascending)
    }

    func shiftMonth(by months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
    }

    static func format(_ times: [TimeOfDay]) -> String {
        times.sorted().map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: ", ")
    }

    static func ascending(_ a: CalendarDate, _ b: CalendarDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

// MARK: - Views

private struct ScheduleEditorView: View {
    @ObservedObject var model: ScheduleEditorModel
    let title: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private let labelWidth: CGFloat = 76

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 15, weight: .semibold))

            row("Name") {
                TextField("Morning reset", text: $model.name)
                    .textFieldStyle(.roundedBorder)
            }
            row("Layout") {
                Picker("Layout", selection: $model.presetIndex) {
                    ForEach(Array(model.presets.enumerated()), id: \.offset) { index, preset in
                        Text("\(preset.name) (\(preset.displaySetupName))").tag(index)
                    }
                }
                .labelsHidden()
            }
            row("Repeat") {
                Picker("Repeat", selection: $model.pattern) {
                    ForEach(ScheduleEditorModel.Pattern.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            switch model.pattern {
            case .weekly:
                row("Days", alignment: .top) { WeekStrip(model: model) }
                timesRow
            case .dates:
                row("Dates", alignment: .top) { MonthGrid(model: model) }
                timesRow
            }


            Text(model.problem ?? hint)
                .font(.system(size: 11))
                .foregroundStyle(model.problem == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, labelWidth + 10)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.problem != nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hint: String {
        switch model.pattern {
        case .weekly: return "Restores the layout on each chosen day, at each time."
        case .dates: return "Restores the layout on each chosen date, at each time. Past dates are skipped."
        }
    }

    private var timesRow: some View {
        row("Times") {
            TextField("09:00, 17:30", text: $model.timesText)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func row<Content: View>(_ label: String,
                                    alignment: VerticalAlignment = .firstTextBaseline,
                                    @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: alignment, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
                .padding(.top, alignment == .top ? 6 : 0)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Monday to Sunday as seven tiles; click to turn a day on or off. Shortcuts
/// underneath pick the common sets in one click.
private struct WeekStrip: View {
    @ObservedObject var model: ScheduleEditorModel

    private let order: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    private let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    private let weekend: Set<Weekday> = [.saturday, .sunday]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(order, id: \.self) { day in
                    DayTile(title: name(of: day), isOn: model.weekdays.contains(day)) {
                        model.toggle(day)
                    }
                }
            }
            HStack(spacing: 10) {
                quick("Weekdays", weekdays)
                quick("Weekends", weekend)
                quick("Every day", Set(order))
            }
        }
    }

    private func name(of day: Weekday) -> String {
        model.calendar.shortWeekdaySymbols[day.rawValue - 1]
    }

    private func quick(_ title: String, _ days: Set<Weekday>) -> some View {
        Button(title) { model.weekdays = days }
            .buttonStyle(.link)
            .font(.system(size: 11))
            .disabled(model.weekdays == days)
    }
}

private struct DayTile: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.white : .primary)
                .frame(width: 42, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One month as a grid; click days to add or remove them. Past days can't be
/// added (they never fire) but can be removed.
private struct MonthGrid: View {
    @ObservedObject var model: ScheduleEditorModel

    private var cal: Calendar { model.calendar }

    /// Leading blanks so the 1st lands under its weekday, then the month's days.
    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: model.month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: model.month)
        let blanks = (firstWeekday - cal.firstWeekday + 7) % 7
        let days = range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: model.month) }
        return Array(repeating: nil, count: blanks) + days
    }

    private var weekdayInitials: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        return (0..<7).map { symbols[(cal.firstWeekday - 1 + $0) % 7] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.month.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Button { model.shiftMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .help("Previous month")
                Button { model.shiftMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)
                    .help("Next month")
            }
            let columns = Array(repeating: GridItem(.fixed(36), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(weekdayInitials.indices, id: \.self) { index in
                    Text(weekdayInitials[index])
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }
            HStack {
                Text(model.dates.isEmpty
                     ? "No dates chosen"
                     : "\(model.dates.count) date\(model.dates.count == 1 ? "" : "s") chosen")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !model.dates.isEmpty {
                    Button("Clear") { model.dates = [] }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
        }
        .frame(width: 36 * 7 + 4 * 6)
    }

    private func dayCell(_ date: Date) -> some View {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        let day = CalendarDate(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
        let isOn = model.dates.contains(day)
        let isPast = cal.startOfDay(for: date) < cal.startOfDay(for: Date())
        let isToday = cal.isDateInToday(date)
        return Button { model.toggle(day) } label: {
            Text("\(c.day ?? 0)")
                .font(.system(size: 12, weight: isOn ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(isOn ? Color.white : (isPast ? Color.secondary.opacity(0.5) : .primary))
                .frame(width: 36, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isToday && !isOn ? 1 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isPast && !isOn)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
