import AppKit
import SwiftUI

/// The welcome tour: a small checklist that stays on top while the user does
/// the real first steps, and ticks each one off when it actually happens.
///
/// 1. Turn on Finder access (notifications alongside, optional).
/// 2. Save the desktop as a layout.
/// 3. Move an icon, then restore the layout and watch it come back.
/// 4. Optional extras: use it for auto-restore, give it a shortcut.
///
/// It finishes with Show Me Around, which opens the menu bar panel and walks
/// through it with highlights (`PanelTourStop`). Opened on first launch and
/// from Settings → Permissions → Welcome tour.
final class WelcomeTour: NSObject, NSWindowDelegate {
    private static var shared: WelcomeTour?

    private let window: NSPanel
    private let state = WelcomeTourState()
    private let watchToken = UUID()

    /// `startPanelTour` opens the panel with its highlights.
    static func show(model: AppModel, actions: UIActions, startPanelTour: @escaping () -> Void) {
        if shared == nil {
            shared = WelcomeTour(model: model, actions: actions, startPanelTour: startPanelTour)
        }
        shared?.present()
    }

    private init(model: AppModel, actions: UIActions, startPanelTour: @escaping () -> Void) {
        window = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: true)
        super.init()
        window.title = "Welcome to DeskStop"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // On top, but not modal: the user has to reach the desktop, Finder
        // and the menu bar panel to do the steps.
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.delegate = self

        let view = WelcomeTourView(model: model, state: state,
                                   finish: { [weak self] in self?.finish(showPanel: false) },
                                   showMeAround: { [weak self] in
                                       self?.finish(showPanel: false)
                                       DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: startPanelTour)
                                   })
            .environment(\.uiActions, actions)
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host

        NotificationCenter.default.addObserver(
            self, selector: #selector(layoutRestored(_:)),
            name: PresetActionsController.didRestoreLayout, object: nil)
    }

    private func present() {
        state.restoredSinceStart = false
        PermissionCenter.shared.beginWatching(watchToken)
        NSApp.activate(ignoringOtherApps: true)
        window.layoutIfNeeded()
        if let screen = NSScreen.main?.visibleFrame {
            // Upper middle, clear of the right-hand column where macOS puts
            // desktop icons by default.
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2,
                                          y: screen.maxY - size.height - screen.height * 0.12))
        }
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func layoutRestored(_ note: Notification) {
        DispatchQueue.main.async { self.state.restoredSinceStart = true }
    }

    private func finish(showPanel: Bool) {
        UserDefaults.standard.hasCompletedOnboarding = true
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window counts as finishing: it won't open by itself again.
        UserDefaults.standard.hasCompletedOnboarding = true
        PermissionCenter.shared.endWatching(watchToken)
    }
}

/// What the tour has seen happen while it was open.
final class WelcomeTourState: ObservableObject {
    @Published var restoredSinceStart = false
}

struct WelcomeTourView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: WelcomeTourState
    @ObservedObject private var permissions = PermissionCenter.shared
    @Environment(\.uiActions) private var actions
    let finish: () -> Void
    let showMeAround: () -> Void

    private var finderOn: Bool { permissions.finderAutomation == .granted }
    private var notificationsOn: Bool { permissions.notifications == .granted }
    /// The layout the tour talks about: the first one for these displays.
    private var layout: ConfigurationSummary? { model.snapshot.currentGroup.configurations.first }
    private var saved: Bool { layout != nil }
    private var restored: Bool { state.restoredSinceStart }

    private var stepsDone: Int { [finderOn, saved, restored].filter { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BrandBadge(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to DeskStop")
                        .font(.system(size: 17, weight: .bold))
                    Text("Save where your desktop icons are, and put them back in one click. Three quick steps:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                TourStep(number: 1, title: "Turn on Finder access", done: finderOn, active: !finderOn,
                         detail: "DeskStop moves your icons through Finder, so macOS has to allow it.") {
                    Button("Turn On") { actions.turnOn(.finderAutomation) }
                        .buttonStyle(.borderedProminent)
                }
                Divider().padding(.leading, 36)
                TourStep(number: 2, title: "Save your desktop as a layout",
                         done: saved, active: finderOn && !saved,
                         detail: saved
                             ? "Saved \u{201C}\(layout?.name ?? "")\u{201D} for \(model.snapshot.currentDisplayLabel)."
                             : "Arrange your icons how you like them, then save them as a layout.") {
                    VStack(alignment: .leading, spacing: 10) {
                        LayoutContents()
                        Button("New Layout", action: actions.newConfiguration)
                            .buttonStyle(.borderedProminent)
                            .disabled(!finderOn)
                    }
                }
                Divider().padding(.leading, 36)
                TourStep(number: 3, title: "Move an icon, then restore",
                         done: restored, active: saved && !restored,
                         detail: restored
                             ? "That's it: your icons went back where they were saved."
                             : "Drag any desktop icon somewhere else, then restore the layout and watch it snap back.") {
                    if let layout {
                        Button("Restore \u{201C}\(layout.name)\u{201D}") { actions.restore(layout.id) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04)))

            if let layout {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extras").font(.system(size: 12, weight: .semibold))
                    ExtraRow(symbol: "star", title: "Restore it when you connect these displays",
                             done: layout.isDefault) {
                        Button("Use for Auto-Restore") { actions.toggleDefault(layout.id) }
                    }
                    ExtraRow(symbol: "command", title: "Restore it with a keyboard shortcut",
                             done: layout.shortcut != nil, doneText: layout.shortcut) {
                        Button("Set Shortcut") { actions.setShortcut(layout.id) }
                    }
                    ExtraRow(symbol: "bell", title: "Get a banner after each restore",
                             done: notificationsOn) {
                        Button("Turn On") { actions.turnOn(.notifications) }
                    }
                }
            }

            HStack {
                Text("\(stepsDone) of 3 done")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(stepsDone == 3 ? "Done" : "Skip Tour", action: finish)
                Button("Show Me Around", action: showMeAround)
                    .keyboardShortcut(stepsDone == 3 ? .defaultAction : nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.2), value: stepsDone)
    }
}

/// One numbered step: a circle that becomes a tick, a title, a line of
/// explanation, and (while it's the step to do) its button.
private struct TourStep<Action: View>: View {
    let number: Int
    let title: String
    let done: Bool
    let active: Bool
    let detail: String
    @ViewBuilder let action: Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : (active ? Color.accentColor : Color.secondary.opacity(0.25)))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(active ? Color.white : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(done || active ? .primary : .secondary)
                if done || active {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if active {
                    action.padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number), \(title)\(done ? ", done" : "")")
    }
}

/// What saving a layout records, shown while that is the step to do. The
/// display lines keep position and resolution apart, and say the second is
/// only changed when asked: "display arrangement" is easy to read as every
/// display setting.
private struct LayoutContents: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("A layout saves:")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            item("square.grid.3x3", "Where each desktop icon is.")
            item("display.2", "Where your displays sit relative to each other, and which one is main: the one with the menu bar.")
            item("aspectratio", "Each display's resolution and refresh rate, changed back only if you turn that on.")
            item("app.badge", "If you choose, apps to open when it's restored.")
        }
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ExtraRow<Action: View>: View {
    let symbol: String
    let title: String
    let done: Bool
    var doneText: String?
    @ViewBuilder let action: Action

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .frame(width: 20)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 6)
            if done {
                Text(doneText ?? "On")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                action.controlSize(.small)
            }
        }
    }
}
