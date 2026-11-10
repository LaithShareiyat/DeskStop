import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The pages in Settings' sidebar.
enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general, layouts, displays, shortcuts, schedules, experimental, backup, permissions, updates, feedback, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .layouts: return "Layouts"
        case .displays: return "Display Setups"
        case .shortcuts: return "Shortcuts"
        case .schedules: return "Schedules"
        case .experimental: return "Experimental"
        case .backup: return "Backup"
        case .permissions: return "Permissions"
        case .updates: return "Updates"
        case .feedback: return "Feedback"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .layouts: return "square.grid.3x3"
        case .displays: return "display.2"
        case .shortcuts: return "command"
        case .schedules: return "clock"
        case .experimental: return "testtube.2"
        case .backup: return "externaldrive"
        case .permissions: return "hand.raised"
        case .updates: return "arrow.down.circle"
        case .feedback: return "bubble.left.and.bubble.right"
        case .about: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Startup, appearance, notifications and hidden icons."
        case .layouts: return "What each layout restores, its shortcut and its apps."
        case .displays: return "Name the display setups DeskStop knows about, and give them icons."
        case .shortcuts: return "Keyboard shortcuts that work in any app."
        case .schedules: return "Restore a layout at set times."
        case .experimental: return "Features still being refined."
        case .backup: return "Keep a copy of your layouts, or move them to another Mac."
        case .permissions: return "What macOS must allow for DeskStop to move your icons."
        case .updates: return "Get new versions from GitHub."
        case .feedback: return "Report a bug or suggest a feature."
        case .about: return "DeskStop for macOS."
        }
    }

    struct Section: Identifiable {
        let title: String
        let pages: [SettingsPage]
        var id: String { title }
    }

    static let sections: [Section] = {
        let sections = [
            Section(title: "Essentials", pages: [.general, .layouts, .displays, .shortcuts]),
            Section(title: "Automation", pages: [.schedules, .experimental]),
            Section(title: "Data", pages: [.backup]),
            Section(title: "DeskStop", pages: [.permissions, .updates, .feedback, .about]),
        ]
        // The sidebar is the only way to reach a page, so a page left out of
        // every section could never be opened. Each page, exactly once.
        let listed = sections.flatMap(\.pages)
        assert(listed.count == allCases.count && Set(listed) == Set(allCases),
               "Every SettingsPage must be in exactly one sidebar section")
        return sections
    }()
}

/// Which page Settings shows; shared so the panel can open a specific one.
final class SettingsRouter: ObservableObject {
    @Published var page: SettingsPage = .general
    /// The layout Settings → Layouts shows; nil picks the first one.
    @Published var layout: UUID?
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var router: SettingsRouter

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(SettingsPage.sections) { section in
                    SidebarSection(section: section)
                }
            }
            .listStyle(.sidebar)
            .modifier(SolidSidebarBeforeLiquidGlass())
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            SettingsDetail(model: model, router: router, page: router.page)
        }
        .frame(minWidth: SettingsWindow.minimumContentSize.width,
               minHeight: SettingsWindow.minimumContentSize.height)
    }

    /// A sidebar list can clear its selection (Command-click the selected
    /// row), which would leave no row highlighted. Ignoring that keeps the
    /// page that's showing selected.
    private var selection: Binding<SettingsPage?> {
        Binding(get: { router.page }, set: { if let page = $0 { router.page = page } })
    }
}

/// One sidebar group, always expanded.
private struct SidebarSection: View {
    let section: SettingsPage.Section

    var body: some View {
        Section(section.title) { rows }
            .collapsible(false)
    }

    private var rows: some View {
        ForEach(section.pages) { page in
            Label(page.title, systemImage: page.symbol)
                .tag(page)
        }
    }
}

/// Before Liquid Glass the sidebar gets a solid background; from macOS 26
/// the system's glass sidebar is left alone.
private struct SolidSidebarBeforeLiquidGlass: ViewModifier {
    func body(content: Content) -> some View {
        if PanelStyle.systemDrawsLiquidGlass {
            content
        } else {
            content
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct SettingsDetail: View {
    @ObservedObject var model: AppModel
    @ObservedObject var router: SettingsRouter
    let page: SettingsPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.title)
                        .font(.system(size: 22, weight: .bold))
                    Text(page.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 900, alignment: .leading)
            // Centred, so widening the window adds equal margins either side.
            .frame(maxWidth: .infinity, alignment: .center)
        }
        // A new scroll view per page, so each opens at its top rather than
        // where the last page was scrolled to.
        .id(page)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .general: GeneralSettings(model: model)
        case .layouts: LayoutSettings(model: model, router: router)
        case .displays: DisplaySetupSettings(model: model)
        case .shortcuts: ShortcutSettings(model: model)
        case .schedules: ScheduleSettings(model: model)
        case .experimental: ExperimentalSettings(model: model)
        case .backup: BackupSettings()
        case .permissions: PermissionSettings()
        case .updates: UpdateSettings(model: model)
        case .feedback: FeedbackSettings()
        case .about: AboutSettings()
        }
    }
}

// MARK: - Building blocks

/// Rounded, outlined background for one group on a Settings page, with an
/// optional heading.
struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(shape.fill(Color.primary.opacity(scheme == .dark ? 0.05 : 0.035)))
        .overlay(shape.strokeBorder(PanelStyle.border(scheme), lineWidth: 0.7))
    }
}

/// A Settings row: tinted icon tile, then title and caption, then the
/// control at the far right. Labels lead and controls trail, the layout Apple
/// gives grouped forms (`FormStyle.grouped`).
struct SettingsRow<Accessory: View>: View {
    let symbol: String
    let title: String
    var caption: String?
    var captionColor: Color = .secondary
    var tint: Color = .accentColor
    var badge = false
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // Wraps rather than truncating when the row is narrow.
                    Text(title)
                        .fixedSize(horizontal: false, vertical: true)
                    if badge { BetaBadge() }
                }
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(captionColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            // Controls keep their natural size; the words wrap into what is left.
            accessory
                .fixedSize()
        }
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(symbol: String, title: String, caption: String? = nil,
         captionColor: Color = .secondary, tint: Color = .accentColor) {
        self.init(symbol: symbol, title: title, caption: caption,
                  captionColor: captionColor, tint: tint) { EmptyView() }
    }
}

/// A trailing switch for a settings row.
private struct RowSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

/// A recorded chord, or "Not set", with Record / Clear.
private struct ShortcutControl: View {
    let shortcut: String?
    let record: () -> Void
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let shortcut {
                ShortcutPill(text: shortcut)
            } else {
                Text("Not set")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Button("Record", action: record)
            Button("Clear", action: clear)
                .disabled(shortcut == nil)
        }
    }
}

/// Granted / Not granted, as a coloured chip.
private struct StatusChip: View {
    let granted: Bool?

    var body: some View {
        let (text, tint): (String, Color) = {
            switch granted {
            case .some(true): return ("Granted", .green)
            case .some(false): return ("Not granted", .orange)
            case .none: return ("Checking", .secondary)
            }
        }()
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.13)))
    }
}

private struct Footnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }
}

// MARK: - Pages

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiActions) private var actions
    @State private var choosingPicture = false

    /// Banners are switched on here but macOS won't show them.
    private var notificationsBlocked: Bool {
        model.snapshot.showNotifications && model.notificationWarning != nil
    }

    private var notificationCaption: String {
        guard model.snapshot.showNotifications else { return "Off. DeskStop sends no banners." }
        if model.notificationWarning != nil { return "Needs macOS permission to show notifications." }
        return "A banner after each restore or save, and when an automation is skipped."
    }

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "circle.lefthalf.filled", title: "Appearance",
                        caption: "Light, dark, or match macOS.") {
                Picker("Appearance", selection: Binding(get: { model.snapshot.appearanceMode },
                                                        set: { actions.setAppearance($0) })) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        SettingsCard {
            SettingsRow(symbol: "power", title: "Start at login",
                        // Not a stored preference: it's SMAppService's state, so backups skip it.
                        caption: "Opens DeskStop when you log in to your Mac.") {
                RowSwitch(label: "Start at login",
                          isOn: model.toggleBinding(\.startAtLogin, actions.toggleStartAtLogin))
            }
            Divider()
            // One row for notifications: the switch is DeskStop's own; macOS's
            // permission and alert style are fixed by Turn On.
            SettingsRow(symbol: "bell.badge", title: "Notifications",
                        caption: notificationCaption,
                        captionColor: notificationsBlocked ? .orange : .secondary,
                        tint: notificationsBlocked ? .orange : .accentColor) {
                HStack(spacing: 8) {
                    if notificationsBlocked {
                        Button("Turn On") {
                            actions.turnOnNotifications(alertStyleOnly: model.notificationsHiddenByAlertStyle)
                        }
                    }
                    RowSwitch(label: "Notifications",
                              isOn: model.toggleBinding(\.showNotifications, actions.toggleNotifications))
                }
            }
        }
        SettingsCard {
            SettingsRow(symbol: "photo", title: "Hide icons behind",
                        caption: coverCaption,
                        captionColor: pictureMissing ? .orange : .secondary,
                        tint: pictureMissing ? .orange : .accentColor) {
                HStack(spacing: 8) {
                    if model.snapshot.hiddenIconsPicture != nil {
                        Button("Change") { choosingPicture = true }
                        Button("Use Wallpaper") { actions.setHiddenIconsPicture(nil) }
                    } else {
                        Button("Choose Picture") { choosingPicture = true }
                    }
                }
            }
        }
        .sheet(isPresented: $choosingPicture) {
            PictureGallery(selected: model.snapshot.hiddenIconsPicture,
                           choose: { url in
                               choosingPicture = false
                               actions.setHiddenIconsPicture(url)
                           },
                           chooseFile: {
                               choosingPicture = false
                               actions.chooseHiddenIconsPictureFile()
                           },
                           cancel: { choosingPicture = false })
        }
        // The setting reads as general, so say where it applies: both
        // features put the same cover over the desktop.
        Footnote(text: "Used by both ways of hiding your icons: Hide desktop icons, in the menu bar panel's Desktop tab or with its shortcut, and Hide icons while screen sharing, under Experimental.")
    }

    private var pictureMissing: Bool { model.snapshot.hiddenIconsPictureMissing }

    private var coverCaption: String {
        guard let picture = model.snapshot.hiddenIconsPicture else {
            return "A copy of your wallpaper, so the desktop looks the same."
        }
        let name = "\u{201C}\(picture.deletingPathExtension().lastPathComponent)\u{201D}"
        if pictureMissing { return "\(name) can't be found, so your wallpaper is used." }
        return "\(name), so you can tell at a glance that icons are hidden."
    }
}

/// One display setup with an editable name. The field shows the custom name,
/// with the detected one as its placeholder; the change is saved on Return
/// or when the field loses focus.
private struct DisplaySetupNameRow: View {
    let setup: DisplaySetupSummary
    @Environment(\.uiActions) private var actions
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var caption: String {
        var parts = [setup.isCurrent ? "Connected now" : "Not connected"]
        parts.append("\(setup.layoutCount) layout\(setup.layoutCount == 1 ? "" : "s")")
        if setup.customName != nil { parts.append(setup.detectedName) }
        return parts.joined(separator: " · ")
    }

    /// Two lines: what the setup is, then its controls.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(symbol: setup.symbol,
                        title: setup.customName ?? setup.detectedName,
                        caption: caption)
            HStack(spacing: 8) {
                Text("Name")
                    .foregroundStyle(.secondary)
                    .fixedSize()
                TextField(setup.detectedName, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 140, maxWidth: .infinity)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in
                        if !isFocused { commit() }
                    }
                iconMenu
                if setup.customName != nil {
                    Button("Reset Name") {
                        draft = ""
                        actions.renameDisplaySetup(setup.id, to: nil)
                    }
                    .fixedSize()
                }
            }
            .padding(.leading, 40)   // under the title, past the icon tile
        }
        .onAppear { draft = setup.customName ?? "" }
        .onChange(of: setup.customName) { _, name in draft = name ?? "" }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (setup.customName ?? "") else { return }
        actions.renameDisplaySetup(setup.id, to: trimmed)
    }

    /// Choose the setup's icon from a fixed set, or go back to the default.
    private var iconMenu: some View {
        Menu {
            ForEach(DisplaySetupNames.symbolChoices, id: \.symbol) { choice in
                Button {
                    actions.setDisplaySetupSymbol(setup.id, to: choice.symbol)
                } label: {
                    Label(choice.name, systemImage: choice.symbol)
                }
            }
            if setup.hasCustomSymbol {
                Divider()
                Button("Use Default Icon") { actions.setDisplaySetupSymbol(setup.id, to: nil) }
            }
        } label: {
            // A menu button needs a title; an image-only label is dropped.
            Label("Icon", systemImage: setup.symbol)
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("Choose an icon")
        .accessibilityLabel("Icon for \(setup.customName ?? setup.detectedName)")
    }
}

/// Settings → Layouts: every layout, grouped by display setup, and the full
/// set of options for the one selected. This is the one place a layout is
/// edited; the panel's ⋯ menu and the right-click menu only restore,
/// replace and delete.
private struct LayoutSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var router: SettingsRouter
    @Environment(\.uiActions) private var actions
    /// The layout being dragged, so a drop can only land in its own setup.
    @State private var dragging: UUID?
    /// The row the dragged layout is over, highlighted to show where it lands.
    @State private var dropTarget: UUID?

    private var groups: [DisplayGroup] {
        ([model.snapshot.currentGroup] + model.snapshot.otherGroups)
            .filter { !$0.configurations.isEmpty }
    }

    private var selection: (group: DisplayGroup, layout: ConfigurationSummary)? {
        let all = groups.flatMap { group in group.configurations.map { (group, $0) } }
        if let id = router.layout, let match = all.first(where: { $0.1.id == id }) {
            return (match.0, match.1)
        }
        return all.first.map { ($0.0, $0.1) }
    }

    var body: some View {
        if groups.isEmpty {
            SettingsCard {
                SettingsRow(symbol: "square.grid.3x3", title: "No layouts yet",
                            caption: "Arrange your desktop, then save it as a layout.") {
                    Button("New Layout", action: actions.newConfiguration)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                layoutList
                    .frame(width: 180)
                if let selection {
                    LayoutEditor(layout: selection.layout, setupName: selection.group.label,
                                 select: { router.layout = $0 })
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var layoutList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    DisplaySetupHeading(group: group,
                                        isCurrent: group.id == model.snapshot.currentGroup.id)
                    // Indented under their setup, with a guide line down the
                    // left, so a layout is never read as a display setup.
                    VStack(alignment: .leading, spacing: 1) {
                        let ids = group.configurations.map(\.id)
                        ForEach(Array(group.configurations.enumerated()), id: \.element.id) { index, layout in
                            LayoutListRow(layout: layout,
                                          isSelected: layout.id == selection?.layout.id,
                                          isDropTarget: dropTarget == layout.id && dragging != layout.id,
                                          select: { router.layout = layout.id },
                                          drag: {
                                              dragging = layout.id
                                              return NSItemProvider(object: layout.id.uuidString as NSString)
                                          })
                            .onDrop(of: [UTType.text],
                                    delegate: LayoutDropDelegate(target: layout.id, ids: ids,
                                                                 setup: group.id,
                                                                 dragging: $dragging,
                                                                 dropTarget: $dropTarget,
                                                                 actions: actions))
                            .contextMenu {
                                Button("Move Up") {
                                    actions.moveLayout(layout.id, by: -1, in: ids, setup: group.id)
                                }
                                .disabled(index == 0)
                                Button("Move Down") {
                                    actions.moveLayout(layout.id, by: 1, in: ids, setup: group.id)
                                }
                                .disabled(index == ids.count - 1)
                            }
                        }
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 1)
                            .padding(.leading, 11)
                            .padding(.vertical, 2)
                    }
                }
            }
            Button(action: actions.newConfiguration) {
                Label("New Layout", systemImage: "plus")
            }
            .padding(.top, 4)
            Text("Drag ≡ to reorder.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

/// Dropping a dragged layout onto another moves it to that position, within
/// the same display setup only.
private struct LayoutDropDelegate: DropDelegate {
    let target: UUID
    let ids: [UUID]
    let setup: String
    @Binding var dragging: UUID?
    @Binding var dropTarget: UUID?
    let actions: UIActions

    func validateDrop(info: DropInfo) -> Bool {
        guard let dragging else { return false }
        return ids.contains(dragging)
    }

    func dropEntered(info: DropInfo) {
        if validateDrop(info: info) { dropTarget = target }
    }

    func dropExited(info: DropInfo) {
        if dropTarget == target { dropTarget = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let id = dragging, ids.contains(id), id != target,
              let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target) else {
            dragging = nil
            dropTarget = nil
            return false
        }
        // Dragging down lands after the target, dragging up before it, which
        // is where the row visibly ends up under the pointer.
        let before: UUID? = from < to ? (to + 1 < ids.count ? ids[to + 1] : nil) : target
        actions.moveLayout(id, before: before, in: ids, setup: setup)
        dragging = nil
        dropTarget = nil
        return true
    }
}

/// A display setup's name above its layouts: its icon, its name in bold,
/// and how many layouts it has. Drawn nothing like a layout row.
private struct DisplaySetupHeading: View {
    let group: DisplayGroup
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(group.label)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(group.configurations.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .help(isCurrent ? "\(group.label), connected now" : group.label)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Display setup \(group.label), \(group.configurations.count) layouts")
    }
}

/// One layout in the list: click to select it, drag the ≡ handle on the
/// right to move it. Not a `Button`: on macOS a button keeps the mouse press,
/// so a drag could never start from it.
private struct LayoutListRow: View {
    let layout: ConfigurationSummary
    let isSelected: Bool
    var isDropTarget = false
    let select: () -> Void
    let drag: () -> NSItemProvider
    @Environment(\.colorScheme) private var scheme
    @State private var hoveringHandle = false

    var body: some View {
        HStack(spacing: 6) {
            // Only the auto-restore layout carries an icon (its star);
            // the rest keep the column empty so names line up.
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14)
                .opacity(layout.isDefault ? 1 : 0)
                .accessibilityHidden(!layout.isDefault)
            Text(layout.name)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 0)
            // A generous target, so the drag is easy to start.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(hoveringHandle ? .primary : .tertiary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .onHover { inside in
                    hoveringHandle = inside
                    if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
                }
                .onDrag(drag)
                .help("Drag to reorder")
                .accessibilityHidden(true)
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? PanelStyle.selectedFill(scheme) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isDropTarget ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
    }
}

/// Everything about one layout, in the order a user decides it: what it is,
/// what restoring it does, how it is triggered, then the destructive actions.
private struct LayoutEditor: View {
    let layout: ConfigurationSummary
    let setupName: String
    /// Selects another layout in the list: the copy, after Duplicate.
    let select: (UUID) -> Void
    @Environment(\.uiActions) private var actions
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(symbol: "pencil", title: "Name") {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.roundedBorder)
                        // Gives way to its label.
                        .frame(minWidth: 120, maxWidth: 200)
                        .focused($nameFocused)
                        .onSubmit(commitName)
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { commitName() }
                        }
                }
                Divider()
                SettingsRow(symbol: "display.2", title: "Display setup", caption: setupName)
            }

            SettingsCard(title: "When restored") {
                SettingsRow(symbol: "square.grid.3x3", title: "Restore icon positions",
                            caption: layout.hasPositions
                                ? "\(layout.iconCount) icon\(layout.iconCount == 1 ? "" : "s") saved."
                                : "No icon positions saved.") {
                    RowSwitch(label: "Restore icon positions",
                              isOn: flag(layout.restoresIcons) { actions.toggleRestoreIcons(layout.id) })
                        .disabled(!layout.hasPositions)
                }
                Divider()
                SettingsRow(symbol: "display", title: "Restore display arrangement",
                            caption: arrangementCaption) {
                    RowSwitch(label: "Restore display arrangement",
                              isOn: flag(layout.restoresDisplays) { actions.toggleRestoreDisplays(layout.id) })
                        .disabled(!layout.hasArrangement)
                }
                Divider()
                SettingsRow(symbol: "aspectratio", title: "Restore resolution and refresh rate",
                            caption: modesCaption) {
                    RowSwitch(label: "Restore resolution and refresh rate",
                              isOn: flag(layout.restoresDisplayModes) { actions.toggleRestoreModes(layout.id) })
                        .disabled(!layout.hasModes)
                }
                Divider()
                SettingsRow(symbol: "app.badge", title: "Open saved apps",
                            caption: layout.hasApps
                                ? layout.appNames.joined(separator: ", ")
                                : "No apps saved. Choose the apps to open with this layout.") {
                    HStack(spacing: 8) {
                        Button(layout.hasApps ? "Change" : "Choose Apps") { actions.captureApps(layout.id) }
                        if layout.hasApps {
                            Button("Clear") { actions.clearApps(layout.id) }
                        }
                        RowSwitch(label: "Open saved apps",
                                  isOn: flag(layout.launchesApps) { actions.toggleLaunchApps(layout.id) })
                            .disabled(!layout.hasApps)
                    }
                }
            }

            SettingsCard(title: "Triggers") {
                SettingsRow(symbol: "star", title: "Use for auto-restore",
                            caption: "Restores this layout when you switch to \(setupName). Only one layout per display setup can auto-restore.") {
                    RowSwitch(label: "Use for auto-restore",
                              isOn: flag(layout.isDefault) { actions.toggleDefault(layout.id) })
                }
                Divider()
                SettingsRow(symbol: "command", title: "Shortcut",
                            caption: "Restores this layout from any app.") {
                    ShortcutControl(shortcut: layout.shortcut,
                                    record: { actions.setShortcut(layout.id) },
                                    clear: { actions.removeShortcut(layout.id) })
                }
            }

            SettingsCard {
                SettingsRow(symbol: "arrow.counterclockwise", title: "Restore now") {
                    Button("Restore") { actions.restore(layout.id) }
                }
                Divider()
                SettingsRow(symbol: "square.and.arrow.down", title: "Replace with current desktop",
                            caption: "Saves your desktop as it is now into this layout.") {
                    Button("Replace") { actions.updateFromDesktop(layout.id) }
                }
                Divider()
                SettingsRow(symbol: "plus.square.on.square", title: "Duplicate layout",
                            caption: "Makes a copy for the same display setup, to change without losing this one.") {
                    Button("Duplicate") { actions.duplicate(layout.id, then: select) }
                }
                Divider()
                SettingsRow(symbol: "trash", title: "Delete layout", tint: .red) {
                    Button("Delete", role: .destructive) { actions.delete(layout.id) }
                }
            }
        }
        .onAppear { draftName = layout.name }
        .onChange(of: layout.id) { _, _ in draftName = layout.name }
        .onChange(of: layout.name) { _, name in draftName = name }
    }

    private var arrangementCaption: String {
        guard layout.hasArrangement else { return "No display arrangement saved." }
        var text = "\(layout.displayCount) display\(layout.displayCount == 1 ? "" : "s") saved"
        if let main = layout.mainDisplayName { text += ", \(main) as main" }
        // Resolution has its own row, right below, which is what stops
        // "display arrangement" reading as every display setting.
        return text + ". Moves each display back to where it sat relative to the others, "
            + "and makes the same one main (the one with the menu bar)."
    }

    private var modesCaption: String {
        guard layout.hasModes else {
            return "Not saved with this layout. Replace with current desktop to save them."
        }
        // The fallbacks, said up front: a dock or cable can stop a display
        // showing what it showed when the layout was saved.
        return layout.displayModes.joined(separator: "; ") + ". "
            + "Falls back to the nearest refresh rate, or leaves a display alone "
            + "if it can't show its resolution."
    }

    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { draftName = layout.name; return }
        guard trimmed != layout.name else { return }
        actions.rename(layout.id, to: trimmed)
    }

    private func flag(_ value: Bool, _ toggle: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { value }, set: { if $0 != value { toggle() } })
    }
}

/// Settings → Display Setups: every setup DeskStop knows about, each with a
/// name the user can change.
private struct DisplaySetupSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard {
            ForEach(Array(model.snapshot.displaySetups.enumerated()), id: \.element.id) { index, setup in
                if index > 0 { Divider() }
                DisplaySetupNameRow(setup: setup)
            }
        }
        Footnote(text: "Give a display setup a name and icon you'll recognise, like Office or Home. Leave the name empty to use the one macOS reports. Setups appear here once you connect them or save a layout for them.")
    }
}

private struct ShortcutSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiActions) private var actions

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "arrow.triangle.2.circlepath", title: "Restore next layout",
                        caption: "Shows this display setup's layouts; press again to move on, and the one you stop on is restored.") {
                ShortcutControl(shortcut: model.snapshot.cycleShortcut,
                                record: actions.recordCycleShortcut,
                                clear: actions.clearCycleShortcut)
            }
            Divider()
            SettingsRow(symbol: "eye.slash", title: "Hide desktop icons",
                        caption: "Hides your desktop icons, or shows them again.") {
                ShortcutControl(shortcut: model.snapshot.hideShortcut,
                                record: actions.recordHideShortcut,
                                clear: actions.clearHideShortcut)
            }
        }
        Footnote(text: "To give a layout its own shortcut, record one for it under Layouts.")
    }
}

private struct ScheduleSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiActions) private var actions

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "clock", title: "Schedules",
                        caption: caption) {
                Button("Open Schedules", action: actions.openSchedules)
            }
        }
        Footnote(text: "A schedule restores a layout on chosen days of the week or on chosen dates. It runs only while the layout's display setup is connected, and is skipped if the Mac was asleep.")
    }

    private var caption: String {
        let count = model.snapshot.scheduleCount
        if count == 0 { return "No schedules yet." }
        let total = "\(count) schedule\(count == 1 ? "" : "s")"
        return model.snapshot.nextSchedule.map { "\(total). \($0)" } ?? "\(total), nothing scheduled to run."
    }
}

private struct ExperimentalSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiActions) private var actions

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "rectangle.on.rectangle", title: "Hide icons while screen sharing",
                        caption: "Hides your icons while your screen is shared, behind what General › Hide icons behind is set to.",
                        badge: true) {
                RowSwitch(label: "Hide icons while screen sharing",
                          isOn: model.toggleBinding(\.hideOnScreenShare, actions.toggleHideOnScreenShare))
            }
            Divider()
            SettingsRow(symbol: "moon", title: "Restore a layout when a Focus turns on",
                        caption: "Add DeskStop as a Focus filter. Also gives a link for Raycast and Alfred.",
                        badge: true) {
                Button("Set Up", action: actions.openFocusSetup)
            }
        }
    }
}

private struct BackupSettings: View {
    @Environment(\.uiActions) private var actions

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "square.and.arrow.up", title: "Export",
                        caption: "Saves your layouts, schedules, shortcuts and settings to a file.") {
                Button("Export", action: actions.exportSettings)
            }
            Divider()
            SettingsRow(symbol: "square.and.arrow.down", title: "Import",
                        caption: "Brings back the layouts, schedules, shortcuts and settings in an exported file. They replace your current versions of the same ones.") {
                Button("Import", action: actions.importSettings)
            }
        }
    }
}

private struct PermissionSettings: View {
    @Environment(\.uiActions) private var actions
    @ObservedObject private var permissions = PermissionCenter.shared
    @State private var watchToken = UUID()
    @State private var finder: FinderDesktopSettings?

    private var finderCaption: String {
        guard let finder else { return "Checking" }
        if finder.groupBy != "None" {
            return "Stacks are on, so DeskStop can't move icons. Right-click the desktop and turn off Use Stacks."
        }
        if !finder.positionsAreEditable {
            return "Set to \u{201C}\(finder.arrangeBy)\u{201D}, so DeskStop can't move icons. Right-click the desktop and choose Sort By › None."
        }
        return "None, so DeskStop can move your icons."
    }

    var body: some View {
        SettingsCard {
            permissionRow(.finderAutomation, symbol: "folder",
                          caption: "Required. Lets DeskStop read and move your desktop icons. macOS lists it under Privacy & Security → Automation.")
            Divider()
            // Not a permission, but needed before any icon can move.
            SettingsRow(symbol: "arrow.up.arrow.down", title: "Finder's Sort By setting",
                        caption: finderCaption,
                        captionColor: finder.map { $0.positionsAreEditable ? .secondary : .orange } ?? .secondary,
                        tint: finder.map { $0.positionsAreEditable ? .accentColor : .orange } ?? .accentColor)
        }
        .onAppear { finder = FinderSettings.read() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            finder = FinderSettings.read()
        }
        Footnote(text: "Turn On asks macOS. If you said no before, it opens System Settings with a guide. Notifications are under General, and keyboard shortcuts need no permission.")
        SettingsCard {
            SettingsRow(symbol: "sparkles", title: "Welcome tour",
                        caption: "Walks you through saving and restoring a layout, then around the menu bar panel.") {
                Button("Start", action: actions.openWelcome)
            }
        }
        // Re-checked every second while this page is showing, so a switch
        // flipped in System Settings appears here at once.
        .onAppear { permissions.beginWatching(watchToken) }
        .onDisappear { permissions.endWatching(watchToken) }
    }

    private func permissionRow(_ kind: PermissionKind, symbol: String, caption: String) -> some View {
        let status = permissions.status(of: kind)
        return SettingsRow(symbol: symbol, title: kind.title, caption: caption) {
            HStack(spacing: 8) {
                StatusChip(granted: status.map { $0 == .granted })
                if let status, status != .granted {
                    if kind.privacyService != nil {
                        Menu {
                            Button("Start Over") { actions.startOver(kind) }
                        } label: {
                            Text("Turn On")
                        } primaryAction: {
                            actions.turnOn(kind)
                        }
                        .fixedSize()
                        .help("Start Over clears an earlier answer, such as one left by another copy of the app, and asks again.")
                    } else {
                        Button("Turn On") { actions.turnOn(kind) }
                    }
                }
            }
        }
    }
}

private struct UpdateSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiActions) private var actions

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "arrow.triangle.2.circlepath", title: "Check automatically",
                        caption: "Checks GitHub once a day.") {
                RowSwitch(label: "Check for updates automatically",
                          isOn: model.toggleBinding(\.automaticallyCheckForUpdates,
                                                    actions.toggleAutomaticUpdateChecks))
            }
            Divider()
            SettingsRow(symbol: "arrow.down.circle", title: "Version \(model.snapshot.appVersion)",
                        caption: "Updates install only when you choose Install and Relaunch.") {
                Button("Check Now", action: actions.checkForUpdates)
            }
        }
        Footnote(text: "DeskStop is free and open source. Releases are published on GitHub.")
    }
}

private struct FeedbackSettings: View {
    @Environment(\.uiActions) private var actions
    @State private var copied = false

    var body: some View {
        SettingsCard {
            SettingsRow(symbol: "ladybug", title: "Report a bug",
                        caption: "Something isn't working as it should. Opens a new issue on GitHub with the details below filled in; add what you did and what happened.") {
                Button("Report a Bug", action: actions.reportBug)
            }
            Divider()
            SettingsRow(symbol: "lightbulb", title: "Request a feature",
                        caption: "Something DeskStop could do better, or doesn't do yet. Opens a feature request on GitHub.") {
                Button("Request a Feature", action: actions.requestFeature)
            }
        }
        SettingsCard(title: "System details") {
            Text(Feedback.systemDetails)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button(copied ? "Copied" : "Copy") {
                actions.copySystemDetails()
                copied = true
            }
        }
        Footnote(text: "Issues on GitHub are public, so leave out anything private. You'll need a free GitHub account. DeskStop sends nothing itself: the buttons open the page in your browser.")
    }
}

private struct AboutSettings: View {
    @Environment(\.uiActions) private var actions
    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        let build = info?["CFBundleVersion"] as? String
        return "Version \(short)" + (build.map { " (\($0))" } ?? "")
    }

    var body: some View {
        SettingsCard {
            HStack(spacing: 16) {
                BrandBadge(size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DeskStop").font(.system(size: 18, weight: .bold))
                    Text(version).foregroundStyle(.secondary)
                    Text("Saves your desktop layout for each display setup, and puts it back.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if Donations.url != nil {
            SettingsCard {
                SettingsRow(symbol: "cup.and.saucer", title: "Support DeskStop",
                            caption: "DeskStop is free and open source. If it saves you time, you can buy its developer a coffee.") {
                    Button("Buy Me a Coffee", action: actions.openDonations)
                }
            }
        }
        SettingsCard {
            SettingsRow(symbol: "folder", title: "Data folder",
                        caption: "Your layouts, shortcuts, schedules and last undo.") {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([DataFolder.ensured()])
                }
            }
        }
        SettingsCard {
            SettingsRow(symbol: "trash", title: "Uninstall DeskStop",
                        caption: "Removes DeskStop and all its data from this Mac, then moves it to the Trash. You can export a backup first.",
                        tint: .red) {
                Button("Uninstall", role: .destructive, action: actions.uninstall)
            }
        }
    }
}
