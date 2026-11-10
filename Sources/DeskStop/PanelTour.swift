import SwiftUI

/// The stops of the guided pass over the menu bar panel, started from the
/// welcome tour's Show Me Around. It goes tab by tab: each tab's own button
/// first, then every card on it, so nothing is left to "and the rest".
/// Each stop highlights one part of the panel (tagged with `tourAnchor`),
/// switches to the tab that part is on, and explains it in a callout.
enum PanelTourStop: Int, CaseIterable {
    case layoutsTab, displaySetup, layouts, layoutMenu, newLayout
    case automationTab, schedules, experimental
    case desktopTab, hideIcons, nextLayout, shortcuts
    case settings, menuBarIcon

    /// The tab the highlighted part is on; the tour switches to it.
    var tab: PanelTab {
        switch self {
        case .layoutsTab, .displaySetup, .layouts, .layoutMenu, .newLayout: return .configurations
        case .automationTab, .schedules, .experimental: return .automation
        case .desktopTab, .hideIcons, .nextLayout, .shortcuts: return .desktop
        // The footer and header are on every tab: stay on the last one.
        case .settings, .menuBarIcon: return .desktop
        }
    }

    /// The callout's small heading: the tab, or "every tab" for the header
    /// and footer, which aren't on any one of them.
    var section: String {
        switch self {
        case .settings, .menuBarIcon: return "Every tab"
        default: return tab.title
        }
    }

    var title: String {
        switch self {
        case .layoutsTab: return "The Layouts tab"
        case .displaySetup: return "Your display setup"
        case .layouts: return "Your layouts"
        case .layoutMenu: return "Quick actions"
        case .newLayout: return "Save another layout"
        case .automationTab: return "The Automation tab"
        case .schedules: return "Schedules"
        case .experimental: return "Experimental"
        case .desktopTab: return "The Desktop tab"
        case .hideIcons: return "Hide desktop icons"
        case .nextLayout: return "Restore next layout"
        case .shortcuts: return "Keyboard shortcuts"
        case .settings: return "Settings"
        case .menuBarIcon: return "Always in your menu bar"
        }
    }

    var text: String {
        switch self {
        case .layoutsTab:
            return "The first tab lists the layouts you've saved for the displays you're using now."
        case .displaySetup:
            return "The displays connected right now. Each display setup keeps its own layouts. If one is set to auto-restore, it's named here and comes back by itself when you connect these displays."
        case .layouts:
            return "Click a layout to restore it, and your icons go back to where they were saved. A star marks the auto-restore layout."
        case .layoutMenu:
            return "The ⋯ button opens a drop-down of quick actions for that layout."
        case .newLayout:
            return "Saves your desktop as it is right now as a new layout for these displays."
        case .automationTab:
            return "The second tab restores layouts for you."
        case .schedules:
            return "Restores a layout at set times, such as weekdays at 9:00 or on dates you pick."
        case .experimental:
            return "Hide your icons by themselves while your screen is shared, and restore a layout when a Focus turns on. Both are still being tuned."
        case .desktopTab:
            return "The third tab has quick controls for your desktop."
        case .hideIcons:
            return "Covers your icons with your wallpaper until you show them again. Handy before a screenshot or a presentation."
        case .nextLayout:
            return "Steps through this display setup's layouts. Press its shortcut again to move on; the one you stop on is restored."
        case .shortcuts:
            return "Records shortcuts for hiding icons and stepping through layouts. Each layout can also have its own, in Settings → Layouts."
        case .settings:
            return "Where you edit a layout's options and shortcut, name your display setups, and manage permissions and updates."
        case .menuBarIcon:
            return "Click the DeskStop icon in the menu bar to open this panel any time. Right-click it for a quick menu of your layouts."
        }
    }

    /// The stops that apply right now: no ⋯ stop before anything is saved.
    static func stops(hasLayouts: Bool) -> [PanelTourStop] {
        allCases.filter { $0 != .layoutMenu || hasLayouts }
    }
}

struct PanelTourAnchorKey: PreferenceKey {
    static var defaultValue: [PanelTourStop: Anchor<CGRect>] = [:]
    static func reduce(value: inout [PanelTourStop: Anchor<CGRect>],
                       nextValue: () -> [PanelTourStop: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view as what `stop` highlights. Adds to what the views
    /// inside it have marked rather than replacing it: the New Layout row
    /// sits inside the layouts list, and a replacing preference dropped the
    /// row's mark, leaving its stop with nothing to outline.
    func tourAnchor(_ stop: PanelTourStop) -> some View {
        transformAnchorPreference(key: PanelTourAnchorKey.self, value: .bounds) { marks, anchor in
            marks[stop] = anchor
        }
    }
}

/// Dims the panel except for the highlighted part, outlines it, and puts
/// the callout below it (or above, when there isn't room).
struct PanelTourOverlay: View {
    let stop: PanelTourStop
    let stops: [PanelTourStop]
    let rect: CGRect?
    let size: CGSize
    let move: (PanelTourStop?) -> Void
    let openSettings: () -> Void
    @State private var calloutHeight: CGFloat = 150

    private var index: Int { stops.firstIndex(of: stop) ?? 0 }
    private var previous: PanelTourStop? { index > 0 ? stops[index - 1] : nil }
    private var next: PanelTourStop? { index + 1 < stops.count ? stops[index + 1] : nil }

    var body: some View {
        let hole = rect?.insetBy(dx: -4, dy: -4)
        ZStack(alignment: .topLeading) {
            // The dim, with a hole over the highlighted part. Clicks on the
            // dim do nothing, so the tour isn't left half-way by accident.
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 10, height: 10)) }
            }
            .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture {}

            if let hole {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .allowsHitTesting(false)
            }

            callout
                .frame(width: size.width - 24)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CalloutHeightKey.self, value: proxy.size.height)
                })
                .offset(x: 12, y: calloutY(hole: hole))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onPreferenceChange(CalloutHeightKey.self) { height in
            if height > 0 { calloutHeight = height }
        }
        .animation(.easeInOut(duration: 0.2), value: stop)
    }

    private func calloutY(hole: CGRect?) -> CGFloat {
        guard let hole else { return (size.height - calloutHeight) / 2 }
        let below = hole.maxY + 10
        if below + calloutHeight <= size.height { return below }
        return max(hole.minY - calloutHeight - 10, 8)
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(stop.section.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Button { move(nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("End the tour")
                .accessibilityLabel("End the tour")
            }
            Text(stop.title).font(.system(size: 13, weight: .semibold))
            Text(stop.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Text("\(index + 1) of \(stops.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if previous != nil {
                    Button("Back") { move(previous) }
                }
                if stop == .settings {
                    Button("Open Settings") {
                        move(nil)
                        openSettings()
                    }
                }
                Button(next == nil ? "Done" : "Next") { move(next) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
    }
}

private struct CalloutHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
