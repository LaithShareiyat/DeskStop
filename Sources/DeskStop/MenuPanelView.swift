import AppKit
import SwiftUI

/// The panel's three pages, picked from the icon tab bar.
enum PanelTab: String, CaseIterable, Identifiable {
    case configurations, automation, desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .configurations: return "Layouts"
        case .automation: return "Automation"
        case .desktop: return "Desktop"
        }
    }

    var symbol: String {
        switch self {
        case .configurations: return "square.grid.3x3"
        case .automation: return "clock.arrow.2.circlepath"
        case .desktop: return "eye.slash"
        }
    }

    /// The walk-through stop that introduces this tab, on its button.
    var tourStop: PanelTourStop {
        switch self {
        case .configurations: return .layoutsTab
        case .automation: return .automationTab
        case .desktop: return .desktopTab
        }
    }
}

/// What left-clicking the menu bar icon opens: a header, an icon tab bar, one
/// page of cards, and Settings / Quit at the foot. Right-click still opens the
/// classic menu, which keeps every action reachable.
struct MenuPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiActions) private var actions
    @AppStorage("panelSelectedTab") private var tabRaw = PanelTab.configurations.rawValue
    /// Every page's height, measured all the time, not only the one showing. The
    /// panel is as tall as the tallest, so switching tabs never resizes it.
    @State private var pageHeights: [PanelTab: CGFloat] = [:]
    /// Display setups whose group is open on the Layouts page. Kept here so the
    /// page's measuring copy opens the same groups.
    @State private var expandedSetups: Set<String>

    /// `expandedSetups` is for the preview renderer, to draw groups open.
    init(model: AppModel, expandedSetups: Set<String> = []) {
        self.model = model
        _expandedSetups = State(initialValue: expandedSetups)
    }

    private var tab: PanelTab { PanelTab(rawValue: tabRaw) ?? .configurations }

    /// Pages taller than this scroll. Measured against the screen holding the
    /// status item (set by `MenuPanelController`), minus room for the header,
    /// tabs, footer and popover arrow.
    private var maxContentHeight: CGFloat {
        let visible = model.panelScreenHeight ?? NSScreen.main?.visibleFrame.height ?? 800
        return max(240, visible - 190)
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            tabBar
            ScrollView(.vertical, showsIndicators: false) {
                page(for: tab)
                    .padding(.bottom, 2)
            }
            .frame(height: min(pageHeights.values.max() ?? 320, maxContentHeight), alignment: .top)
            .background(alignment: .top) { pageMeasurements }
            .onPreferenceChange(PanelPageHeightsKey.self) { heights in
                if heights != pageHeights { pageHeights = heights }
            }
            footer
        }
        .padding(14)
        .frame(width: PanelStyle.panelWidth)
        .overlayPreferenceValue(PanelTourAnchorKey.self) { anchors in
            Group {
                if let stop = model.panelTour {
                    GeometryReader { proxy in
                        PanelTourOverlay(stop: stop,
                                         stops: PanelTourStop.stops(
                                             hasLayouts: !model.snapshot.currentGroup.configurations.isEmpty),
                                         rect: anchors[stop].map { proxy[$0] },
                                         size: proxy.size,
                                         move: move(to:),
                                         openSettings: { actions.openSettings() })
                    }
                }
            }
        }
    }

    /// Every stop shows the tab its highlighted part is on.
    private func move(to stop: PanelTourStop?) {
        if let stop { tabRaw = stop.tab.rawValue }
        model.panelTour = stop
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            BrandMark(size: 14)
            HStack {
                Spacer()
                if model.snapshot.desktopHidden {
                    Label("Icons hidden", systemImage: "eye.slash")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .help("Desktop icons are hidden")
                }
            }
        }
        .frame(height: 24)
        .tourAnchor(.menuBarIcon)
    }

    private var tabBar: some View {
        PanelTabBar(selection: Binding(get: { tab }, set: { tabRaw = $0.rawValue }))
    }

    // MARK: - Pages

    @ViewBuilder
    private func page(for tab: PanelTab) -> some View {
        switch tab {
        case .configurations: ConfigurationsPage(model: model, expanded: $expandedSetups)
        case .automation: AutomationPage(model: model)
        case .desktop: DesktopPage(model: model)
        }
    }

    /// Invisible copies of every page, laid out at their natural height so
    /// each can be measured whichever tab is showing.
    private var pageMeasurements: some View {
        ZStack(alignment: .top) {
            ForEach(PanelTab.allCases) { tab in
                page(for: tab)
                    .padding(.bottom, 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: PanelPageHeightsKey.self,
                                               value: [tab: proxy.size.height])
                    })
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Replaces, so the copies' walk-through marks never reach the
        // overlay: only the page on screen may be outlined.
        .preference(key: PanelTourAnchorKey.self, value: [:])
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            PanelFooterButton(title: "Settings", symbol: "gearshape") { actions.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .tourAnchor(.settings)
            PanelFooterButton(title: "Quit", symbol: "power", action: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

private struct PanelPageHeightsKey: PreferenceKey {
    static var defaultValue: [PanelTab: CGFloat] = [:]
    static func reduce(value: inout [PanelTab: CGFloat], nextValue: () -> [PanelTab: CGFloat]) {
        value.merge(nextValue()) { max($0, $1) }
    }
}

// MARK: - Tab bar

private struct PanelTabBar: View {
    @Binding var selection: PanelTab
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { tab in
                let isActive = tab == selection
                Button { selection = tab } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? PanelStyle.selectedFill(scheme) : Color.clear)
                )
                .help(tab.title)
                .tourAnchor(tab.tourStop)
                // The tabs show only symbols, so give VoiceOver the page name.
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .background(shape.fill(PanelStyle.cardFill(scheme)))
        .overlay(shape.strokeBorder(PanelStyle.border(scheme), lineWidth: 0.7))
    }
}

// MARK: - Configurations page

private struct ConfigurationsPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var permissions = PermissionCenter.shared
    @Environment(\.uiActions) private var actions
    /// Display setups whose group is open. The one in use now is always
    /// open; the rest start folded, since they are rarely restored from here.
    @Binding var expanded: Set<String>

    private var snapshot: PanelSnapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let finder = permissions.finderAutomation, finder != .granted {
                finderAccessCard
            }

            currentDisplayCard
                .tourAnchor(.displaySetup)

            if let undo = snapshot.undoTitle {
                PanelNavigationCard(symbol: "arrow.uturn.backward", title: undo,
                                    caption: "Puts your icons back as they were.",
                                    opensWindow: false,
                                    action: actions.undoLastRestore)
            }

            // The setup in use is what the panel is for, so its list is
            // always open and headed with the setup's own name. Other setups
            // stay folded below.
            PanelSectionTitle("Layouts for \(snapshot.currentDisplayLabel)")
                .lineLimit(1)
                .truncationMode(.middle)
            if snapshot.currentGroup.configurations.isEmpty {
                emptyState
                    .tourAnchor(.layouts)
            } else {
                // New layouts are always saved for the display setup in
                // use, so the button sits at the end of its list and says so.
                ConfigurationList(configurations: snapshot.currentGroup.configurations,
                                  newLayoutTitle: newLayoutTitle,
                                  newLayout: actions.newConfiguration,
                                  marksFirstMenu: true)
                    .tourAnchor(.layouts)
            }

            if !snapshot.otherGroups.isEmpty {
                PanelSectionTitle("Other display setups")
                    .padding(.top, 4)
            }
            ForEach(snapshot.otherGroups) { group in
                PanelDisclosureHeader(title: group.label,
                                      count: group.configurations.count,
                                      isExpanded: binding(for: group.id))
                if expanded.contains(group.id) {
                    ConfigurationList(configurations: group.configurations)
                }
            }
        }
    }

    private var newLayoutTitle: String { "New Layout for \(snapshot.currentDisplayLabel)" }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(key) },
                set: { open in
                    if open { expanded.insert(key) } else { expanded.remove(key) }
                })
    }

    private var currentDisplayCard: some View {
        HStack(spacing: PanelStyle.iconSpacing) {
            PanelRowIcon(symbol: snapshot.currentDisplaySymbol)
            PanelRowText(title: snapshot.currentDisplayLabel,
                         caption: snapshot.defaultConfigurationName
                             .map { "Auto-restores \u{201C}\($0)\u{201D}" } ?? "No auto-restore layout")
            Spacer(minLength: 0)
        }
        .panelRowInsets()
        .panelCard(padded: false)
    }

    /// Without Finder automation nothing can be saved or restored, so this
    /// leads the page until it is on.
    private var finderAccessCard: some View {
        HStack(spacing: PanelStyle.iconSpacing) {
            PanelRowIcon(symbol: "exclamationmark.triangle.fill", tint: .orange)
            PanelRowText(title: "Finder access is off",
                         caption: "Needed to read and move your desktop icons.")
            Spacer(minLength: 6)
            Button("Turn On") { actions.turnOn(.finderAutomation) }
                .controlSize(.small)
        }
        .panelRowInsets()
        .background(
            RoundedRectangle(cornerRadius: PanelStyle.cardRadius, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PanelStyle.cardRadius, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.7)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelRowText(title: "No layouts for these displays yet",
                         caption: "Arrange your desktop, then save it as a layout.")
            Button(action: actions.newConfiguration) {
                Label(newLayoutTitle, systemImage: "plus")
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tourAnchor(.newLayout)
        }
        .padding(12)
        .panelCard(padded: false)
    }
}

/// One card holding a display setup's configurations, split by hairlines,
/// optionally ending with a row that adds a new layout to it.
private struct ConfigurationList: View {
    let configurations: [ConfigurationSummary]
    var newLayoutTitle: String?
    var newLayout: (() -> Void)?
    /// The first row's ⋯ button is what the walk-through's ⋯ stop outlines.
    var marksFirstMenu = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(configurations.enumerated()), id: \.element.id) { index, configuration in
                if index > 0 {
                    Divider()
                        .padding(.leading, PanelStyle.rowHorizontalInset + PanelStyle.iconColumn
                                    + PanelStyle.iconSpacing)
                        .padding(.trailing, PanelStyle.rowHorizontalInset)
                }
                ConfigurationRow(configuration: configuration,
                                 marksMenu: marksFirstMenu && index == 0)
            }
            if let newLayoutTitle, let newLayout {
                Divider()
                    .padding(.horizontal, PanelStyle.rowHorizontalInset)
                NewLayoutRow(title: newLayoutTitle, action: newLayout)
                    .tourAnchor(.newLayout)
            }
        }
        .panelCard(padded: false)
    }
}

/// The last row of the current display setup's list.
private struct NewLayoutRow: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PanelStyle.iconSpacing) {
                PanelRowIcon(symbol: "plus")
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .panelRowInsets()
            .background(PanelRowHighlight(isVisible: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Click to restore; everything else is in the trailing menu.
private struct ConfigurationRow: View {
    let configuration: ConfigurationSummary
    var marksMenu = false
    @Environment(\.uiActions) private var actions
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button { actions.restore(configuration.id) } label: {
                HStack(spacing: PanelStyle.iconSpacing) {
                    PanelRowIcon(symbol: configuration.isDefault ? "star.fill" : "square.grid.3x3",
                                 tint: configuration.isDefault ? .accentColor : .secondary)
                    PanelRowText(title: configuration.name,
                                 caption: configuration.restoreSummary,
                                 captionColor: configuration.restoresNothing ? .orange : .secondary)
                    Spacer(minLength: 4)
                    if let shortcut = configuration.shortcut {
                        ShortcutPill(text: shortcut)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Restore \u{201C}\(configuration.name)\u{201D}")
            .accessibilityLabel("Restore \(configuration.name)")
            .accessibilityHint(configuration.restoreSummary)

            if marksMenu {
                ConfigurationMenu(configuration: configuration)
                    .tourAnchor(.layoutMenu)
            } else {
                ConfigurationMenu(configuration: configuration)
            }
        }
        .panelRowInsets()
        .background(PanelRowHighlight(isVisible: hovering))
        .onHover { hovering = $0 }
    }
}

/// A short menu: replacing and deleting are the only edits worth making
/// without seeing the layout's options. Everything else is one click away in
/// Settings → Layouts.
private struct ConfigurationMenu: View {
    let configuration: ConfigurationSummary
    @Environment(\.uiActions) private var actions

    var body: some View {
        let id = configuration.id
        Menu {
            Button("Replace with Current Desktop") { actions.updateFromDesktop(id) }
            Button("Duplicate") { actions.duplicate(id) }
            Button("Edit in Settings") { actions.editInSettings(id) }
            Divider()
            Button("Delete") { actions.delete(id) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More for \u{201C}\(configuration.name)\u{201D}")
        .accessibilityLabel("More actions for \(configuration.name)")
    }
}

// MARK: - Automation page

private struct AutomationPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelSectionTitle("Automation")
            PanelNavigationCard(symbol: "clock",
                                title: "Schedules",
                                caption: model.snapshot.nextSchedule
                                    ?? (model.snapshot.scheduleCount == 0
                                        ? "Restores a layout at set times."
                                        : "Nothing scheduled to run."),
                                action: actions.openSchedules)
                .tourAnchor(.schedules)

            PanelSectionTitle("Experimental")
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 8) {
                PanelToggleCard(symbol: "rectangle.on.rectangle",
                                title: "Hide icons while screen sharing",
                                caption: "Hides your icons while your screen is shared.",
                                badge: true,
                                isOn: model.toggleBinding(\.hideOnScreenShare, actions.toggleHideOnScreenShare))
                PanelNavigationCard(symbol: "moon",
                                    title: "Focus filter",
                                    caption: "Restores a layout when a Focus turns on.",
                                    badge: true,
                                    action: actions.openFocusSetup)
            }
            .tourAnchor(.experimental)
        }
    }
}

// MARK: - Desktop page

private struct DesktopPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiActions) private var actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelSectionTitle("Desktop")
            PanelToggleCard(symbol: "eye.slash",
                            title: "Hide desktop icons",
                            caption: "Covers your icons with the wallpaper until you show them again.",
                            shortcut: model.snapshot.hideShortcut,
                            isOn: model.toggleBinding(\.desktopHidden, actions.toggleHideDesktop))
                .tourAnchor(.hideIcons)
            PanelNavigationCard(symbol: "arrow.triangle.2.circlepath",
                                title: "Restore next layout",
                                caption: "Shows this display setup's layouts; press again to move on, and the one you stop on is restored.",
                                shortcut: model.snapshot.cycleShortcut,
                                opensWindow: false,
                                action: actions.cycleConfigurations)
                .tourAnchor(.nextLayout)
            PanelNavigationCard(symbol: "command",
                                title: "Keyboard shortcuts",
                                caption: "Set shortcuts for hiding icons and the next layout.",
                                action: { actions.openSettings(page: .shortcuts) })
                .tourAnchor(.shortcuts)
        }
    }
}
