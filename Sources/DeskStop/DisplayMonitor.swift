import AppKit
import DisplayCore

final class DisplayMonitor {
    /// How long to wait after the last raw event before firing `onChange`. A
    /// dock/undock posts several screen-parameter events in quick succession, and
    /// sampling mid-burst can catch a display that has briefly vanished.
    static let settleInterval: TimeInterval = 0.75

    /// Suppresses reaction to display changes the app caused itself.
    private var suppression = SuppressionWindow()

    /// Ignore display-change events for `seconds`. Called before the app
    /// deliberately rearranges displays, so the resulting notifications don't
    /// re-trigger the restore that caused them.
    func suppress(for seconds: TimeInterval) {
        suppression.suppress(until: Date().addingTimeInterval(seconds))
    }

    /// Snapshot of the current display arrangement. Always reads fresh from
    /// `NSScreen.screens` so the caller never holds stale data after a
    /// hot-plug.
    var currentConfiguration: DisplayConfiguration {
        DisplayConfiguration.current()
    }

    /// Fired on the main thread whenever the screen arrangement changes —
    /// callers can re-evaluate which preset variant applies, refresh menus,
    /// or trigger auto-restore.
    var onChange: (() -> Void)?

    private var settleTimer: Timer?

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    /// Force a debounced re-evaluation. Useful when an external signal
    /// (system wake, etc.) suggests the display arrangement may have
    /// changed without AppKit posting a screens-changed notification.
    func recheck() {
        DispatchQueue.main.async { [weak self] in
            self?.scheduleSettle(reason: "external recheck")
        }
    }

    @objc private func screensChanged() {
        scheduleSettle(reason: "screens changed")
    }

    @objc private func systemDidWake() {
        // After wake, displays can reattach without AppKit posting a
        // screens-changed event. Probe the configuration through the same
        // debounce so the auto-restore path runs if it actually differs.
        scheduleSettle(reason: "system woke")
    }

    private func scheduleSettle(reason: String) {
        settleTimer?.invalidate()
        // .common mode so the settle timer still fires while a menu is open.
        let t = Timer(timeInterval: Self.settleInterval, repeats: false) { [weak self] _ in
            self?.fireOnChange(reason: reason)
        }
        RunLoop.main.add(t, forMode: .common)
        settleTimer = t
    }

    private func fireOnChange(reason: String) {
        if suppression.isSuppressed(now: Date()) {
            NSLog("DeskStop ignoring self-induced screen change (\(reason))")
            return
        }
        let config = currentConfiguration
        NSLog("DeskStop screens settled (\(reason)): \(config.label) (key=\(config.key))")
        onChange?()
    }
}
