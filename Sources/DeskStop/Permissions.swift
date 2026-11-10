import AppKit
import ApplicationServices
import UserNotifications

enum PermissionStatus {
    case notDetermined  // User hasn't been asked yet
    case granted        // User said yes
    case denied         // User said no — must visit System Settings to undo
}

/// Status + request helpers for the three permissions DeskStop needs.
enum Permissions {

    // MARK: - Finder Automation (AppleEvents)

    /// Sending an AppleEvent to Finder triggers an Automation prompt the first
    /// time. `AEDeterminePermissionToAutomateTarget` checks the status (and can
    /// trigger the prompt) without running a script.
    static func finderAutomationStatus() -> PermissionStatus {
        return queryFinderAutomation(askIfNeeded: false)
    }

    /// Triggers the Automation prompt for Finder if the user hasn't been
    /// asked yet. Returns the resulting status. Safe to call from the main
    /// thread; the prompt is system-modal.
    @discardableResult
    static func requestFinderAutomation() -> PermissionStatus {
        return queryFinderAutomation(askIfNeeded: true)
    }

    private static func queryFinderAutomation(askIfNeeded: Bool) -> PermissionStatus {
        // Build an AEDesc for the Finder bundle target.
        var target = AEAddressDesc()
        let bundleID = "com.apple.finder"
        let bytes = Array(bundleID.utf8)
        let createErr = bytes.withUnsafeBufferPointer { buf in
            AECreateDesc(DescType(typeApplicationBundleID),
                         buf.baseAddress,
                         buf.count,
                         &target)
        }
        guard createErr == noErr else { return .notDetermined }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            DescType(typeWildCard),
            DescType(typeWildCard),
            askIfNeeded
        )
        // Named constants for the two refusal codes: swapping them offers a prompt
        // macOS will never show again.
        switch Int(status) {
        case Int(noErr):                             return .granted
        case Int(errAEEventNotPermitted):            return .denied         // -1743
        case Int(errAEEventWouldRequireUserConsent): return .notDetermined  // -1744
        default:                                     return .notDetermined  // e.g. procNotFound
        }
    }

    // MARK: - Notifications

    static func notificationsStatus(completion: @escaping (PermissionStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: PermissionStatus
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: status = .granted
            case .denied:                               status = .denied
            case .notDetermined:                        status = .notDetermined
            @unknown default:                           status = .notDetermined
            }
            DispatchQueue.main.async { completion(status) }
        }
    }

    static func requestNotifications(completion: @escaping (PermissionStatus) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                completion(granted ? .granted : .denied)
            }
        }
    }

    /// Opens System Settings → Notifications on DeskStop's own entry, for a
    /// user who denied them: `requestAuthorization` won't prompt again. Falls
    /// back to the Notifications list if the deep link isn't understood.
    static func openNotificationSettings() {
        let pane = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        let target = Bundle.main.bundleIdentifier.map { "\(pane)?id=\($0)" } ?? pane
        if let url = URL(string: target) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Privacy & Security → Automation, where a refused Finder grant can be
    /// switched back on: macOS never shows the consent prompt a second time.
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Forgets every answer macOS holds for this app under one privacy service
    /// ("AppleEvents", or "All"), so the next request prompts again. Ad-hoc
    /// signed rebuilds need this: the old entry no longer matches. `tccutil`
    /// works on the caller's own entries. Returns false if it failed or took more
    /// than five seconds.
    @discardableResult
    static func resetPrivacyAnswers(service: String) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return false }
        guard done.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    // MARK: - Accessibility (for global hotkeys)

    static func accessibilityStatus() -> PermissionStatus {
        // `AXIsProcessTrustedWithOptions(nil)` returns the current state
        // without prompting and without leaning on the cached value
        // `AXIsProcessTrusted()` sometimes serves stale.
        return AXIsProcessTrustedWithOptions(nil) ? .granted : .notDetermined
    }

    /// Opens System Settings → Privacy & Security → Accessibility. We don't also
    /// call `AXIsProcessTrustedWithOptions(prompt: true)`: its prompt leads to the
    /// same pane and the two would stack. The user must flip the toggle.
    static func requestAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension UserDefaults {
    private static let onboardingKey = "hasCompletedOnboarding"

    var hasCompletedOnboarding: Bool {
        get { bool(forKey: Self.onboardingKey) }
        set { set(newValue, forKey: Self.onboardingKey) }
    }
}

enum AppRelaunch {
    /// Spawns a fresh instance of this .app, then terminates this one. Accessibility
    /// trust only takes effect for processes launched after the toggle. The brief
    /// wait lets the new process claim the menu-bar slot, so the icon flickers
    /// rather than vanishes.
    static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                NSLog("DeskStop relaunch error: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NSApp.terminate(nil)
            }
        }
    }
}
