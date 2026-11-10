import AppKit
import Combine
import SwiftUI

/// The permissions DeskStop asks for from inside the app.
///
/// Accessibility is not here: global hotkeys go through Carbon's
/// `RegisterEventHotKey`, which needs no permission, and nothing else in the
/// app uses the Accessibility API.
enum PermissionKind: String, CaseIterable, Identifiable {
    case finderAutomation, notifications

    var id: String { rawValue }

    /// The row title. macOS files Finder access under Automation; the
    /// caption says so, the title names what it is for.
    var title: String {
        switch self {
        case .finderAutomation: return "Finder"
        case .notifications: return "Notifications"
        }
    }

    /// The guide card's heading while waiting, and once granted. Not built
    /// from `title`: "Turn on Finder" reads as starting the Finder app.
    var guideTitle: String {
        switch self {
        case .finderAutomation: return "Turn on Finder access"
        case .notifications: return "Turn on notifications"
        }
    }

    var grantedTitle: String {
        switch self {
        case .finderAutomation: return "Finder access is on"
        case .notifications: return "Notifications are on"
        }
    }

    /// The privacy service `tccutil` resets for Start Over, or nil when the
    /// permission is not kept by TCC (notifications have their own store).
    var privacyService: String? {
        switch self {
        case .finderAutomation: return "AppleEvents"
        case .notifications: return nil
        }
    }

    /// What the guide card asks the user to do in System Settings.
    var steps: [String] {
        switch self {
        case .finderAutomation:
            return ["System Settings is open at Privacy & Security › Automation.",
                    "Find DeskStop and turn on Finder under it.",
                    "This card closes by itself once it's on."]
        case .notifications:
            return ["System Settings is open at DeskStop's notifications.",
                    "Turn on Allow notifications.",
                    "Set the alert style to Banners."]
        }
    }

    fileprivate func openSettings() {
        switch self {
        case .finderAutomation: Permissions.openAutomationSettings()
        case .notifications: Permissions.openNotificationSettings()
        }
    }
}

/// Live permission status, and the one-click path to turning each one on.
///
/// macOS never lets an app grant itself a permission. This asks with the
/// system prompt while the answer is open, otherwise opens the exact System
/// Settings pane with a floating guide card (`PermissionGuidePanel`), and
/// notices the grant by polling while anything is watching.
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    /// nil until first checked, so nothing warns about a permission it has
    /// not looked at yet.
    @Published private(set) var finderAutomation: PermissionStatus?
    @Published private(set) var notifications: PermissionStatus?

    private var watchers: Set<UUID> = []
    private var timer: Timer?
    private var activeObserver: NSObjectProtocol?

    private init() {
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    func status(of kind: PermissionKind) -> PermissionStatus? {
        switch kind {
        case .finderAutomation: return finderAutomation
        case .notifications: return notifications
        }
    }

    func refresh() {
        #if DEBUG
        if previewFrozen { return }
        #endif
        // A read-only check: never shows a prompt.
        let finder = Permissions.finderAutomationStatus()
        if finder != finderAutomation { finderAutomation = finder }
        // UNUserNotificationCenter raises outside an app bundle (the debug UI
        // renderer), so leave notifications unknown there.
        guard Bundle.main.bundleIdentifier != nil else { return }
        Permissions.notificationsStatus { [weak self] status in
            if self?.notifications != status { self?.notifications = status }
        }
    }

    // MARK: - Watching

    /// While any surface showing permission state is on screen, re-check
    /// every second so a switch flipped in System Settings shows up at once.
    func beginWatching(_ token: UUID) {
        watchers.insert(token)
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func endWatching(_ token: UUID) {
        watchers.remove(token)
        guard watchers.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Turning a permission on

    /// The Turn On button. Asks with the system prompt while macOS will still
    /// show it; once the user has answered no, opens System Settings at the
    /// right pane with the guide card.
    func request(_ kind: PermissionKind) {
        switch (kind, status(of: kind)) {
        case (_, .some(.granted)):
            return
        case (.finderAutomation, .some(.denied)), (.notifications, .some(.denied)):
            guide(kind)
        case (.finderAutomation, _):
            askFinder()
        case (.notifications, _):
            guard Bundle.main.bundleIdentifier != nil else { return }
            Permissions.requestNotifications { [weak self] _ in self?.refresh() }
        }
    }

    /// Clears macOS's stored answer and asks again. For an entry that no
    /// longer matches this copy of the app (a rebuild, or a copy in another
    /// folder), or a "no" the user wants to take back.
    func startOver(_ kind: PermissionKind) {
        guard let service = kind.privacyService else {
            kind.openSettings()
            return
        }
        PermissionGuidePanel.shared.dismiss()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            Permissions.resetPrivacyAnswers(service: service)
            DispatchQueue.main.async {
                self?.refresh()
                self?.request(kind)
            }
        }
    }

    func guide(_ kind: PermissionKind) {
        kind.openSettings()
        PermissionGuidePanel.shared.show(kind)
    }

    /// The Finder consent prompt blocks the calling thread until it is
    /// answered, so it is asked off the main thread to keep the UI live.
    private func askFinder() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let answer = Permissions.requestFinderAutomation()
            DispatchQueue.main.async {
                self?.refresh()
                // No prompt appeared (macOS already holds a "no"), or the
                // user just said no: the only way on is System Settings.
                if answer == .denied { self?.guide(.finderAutomation) }
            }
        }
    }

    #if DEBUG
    /// Set by the debug UI renderer, so its fixtures are not replaced by
    /// this Mac's real answers when a page starts watching.
    private var previewFrozen = false

    func setForPreview(finder: PermissionStatus?, notifications: PermissionStatus?) {
        previewFrozen = true
        finderAutomation = finder
        self.notifications = notifications
    }
    #endif
}

// MARK: - Guide card

/// A small card floating over System Settings while the user switches a
/// permission on. It does not take focus, follows the user across Spaces,
/// and closes itself shortly after macOS reports the grant.
final class PermissionGuidePanel {
    static let shared = PermissionGuidePanel()

    private var panel: NSPanel?
    private var subscription: AnyCancellable?
    private var sizeSubscription: AnyCancellable?
    private var hintWork: DispatchWorkItem?
    private let watchToken = UUID()

    private init() {}

    func show(_ kind: PermissionKind) {
        dismiss()
        let state = PermissionGuideState()
        let card = PermissionGuideCard(kind: kind, state: state,
                                       onOpenSettings: { kind.openSettings() },
                                       onStartOver: { PermissionCenter.shared.startOver(kind) },
                                       onClose: { [weak self] in self?.dismiss() })
        let host = NSHostingView(rootView: card)
        let size = host.fittingSize
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let panel = NSPanel(contentRect: NSRect(x: visible.maxX - size.width - 20,
                                                y: visible.maxY - size.height - 20,
                                                width: size.width, height: size.height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel

        PermissionCenter.shared.beginWatching(watchToken)
        let publisher = kind == .finderAutomation
            ? PermissionCenter.shared.$finderAutomation
            : PermissionCenter.shared.$notifications
        subscription = publisher
            .filter { $0 == .granted }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                state.granted = true
                self?.hintWork?.cancel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    self?.dismiss()
                }
            }
        // The card grows when the hint appears and shrinks once granted;
        // keep its top-right corner where the user saw it.
        sizeSubscription = state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak panel, weak host] _ in
                DispatchQueue.main.async {
                    guard let panel, let host else { return }
                    let size = host.fittingSize
                    let frame = panel.frame
                    panel.setFrame(NSRect(x: frame.maxX - size.width, y: frame.maxY - size.height,
                                          width: size.width, height: size.height),
                                   display: true, animate: true)
                }
            }
        // Long enough for the trip to System Settings; after that the usual
        // cause is an entry left by another copy of the app.
        let hint = DispatchWorkItem { state.showHint = true }
        hintWork = hint
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: hint)
    }

    func dismiss() {
        hintWork?.cancel()
        hintWork = nil
        subscription = nil
        sizeSubscription = nil
        panel?.orderOut(nil)
        panel = nil
        PermissionCenter.shared.endWatching(watchToken)
    }
}

private final class PermissionGuideState: ObservableObject {
    @Published var granted = false
    @Published var showHint = false
}

private struct PermissionGuideCard: View {
    let kind: PermissionKind
    @ObservedObject var state: PermissionGuideState
    let onOpenSettings: () -> Void
    let onStartOver: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: state.granted ? "checkmark.circle.fill" : "hand.raised.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(state.granted ? Color.green : Color.accentColor)
                Text(state.granted ? kind.grantedTitle : kind.guideTitle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 12)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close")
            }
            if !state.granted {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(kind.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.accentColor.opacity(0.15)))
                            Text(step)
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if state.showHint, kind.privacyService != nil {
                    Text("DeskStop not listed, or already on? Another copy of the app may own the entry. Start Over clears it and asks again.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if state.showHint, kind.privacyService != nil {
                        Button("Start Over", action: onStartOver)
                    }
                    Spacer(minLength: 0)
                    Button("Open System Settings", action: onOpenSettings)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(shape.strokeBorder(PanelStyle.border(scheme), lineWidth: 0.7))
        .clipShape(shape)
        .animation(.easeInOut(duration: 0.2), value: state.granted)
        .animation(.easeInOut(duration: 0.2), value: state.showHint)
    }
}
