import AppKit
import CoreGraphics

/// Polls whether the screen is being shared or captured and reports every
/// reading. Makes no hide/show decisions — that's `ShareAutoHidePolicy`.
///
/// Detection combines two signals:
/// - Public: `CGSessionCopyCurrentDictionary`'s `CGSSessionScreenIsShared`,
///   true during Screen Sharing / remote-management sessions.
/// - Private: SkyLight's `CGSIsScreenWatcherPresent`, true while any process
///   captures the screen (Zoom, Meet, OBS, QuickTime; transiently during
///   screenshots). Resolved once via dlsym; if Apple removes the symbol the
///   check contributes false forever and the feature degrades to public-only.
final class ScreenShareMonitor {
    /// One reading per poll, on the main thread.
    var onTick: ((Bool) -> Void)?

    private static let pollInterval: TimeInterval = 2.0
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        // .common mode so polling continues while the status-bar menu is open.
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.onTick?(Self.isScreenBeingCaptured())
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Detection

    static func isScreenBeingCaptured() -> Bool {
        sessionScreenIsShared() || screenWatcherPresent()
    }

    private static func sessionScreenIsShared() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any],
              let shared = dict["CGSSessionScreenIsShared"] as? Bool
        else { return false }
        return shared
    }

    /// `CGSIsScreenWatcherPresent` looked up once. SkyLight is loaded into
    /// every AppKit process, so RTLD_DEFAULT finds it without an explicit
    /// dlopen. nil when the symbol no longer exists.
    private static let watcherPresent: (@convention(c) () -> Bool)? = {
        guard let sym = dlsym(dlopen(nil, RTLD_LAZY), "CGSIsScreenWatcherPresent") else {
            NSLog("DeskStop: CGSIsScreenWatcherPresent unavailable — screen-share detection is public-signal only")
            return nil
        }
        return unsafeBitCast(sym, to: (@convention(c) () -> Bool).self)
    }()

    private static func screenWatcherPresent() -> Bool {
        Self.watcherPresent?() ?? false
    }
}

extension UserDefaults {
    private static let hideOnScreenShareKey = "hideIconsWhenScreenSharing"

    /// EXPERIMENTAL: auto-enable presentation mode while the screen is shared.
    /// Default off.
    var hideIconsWhenScreenSharing: Bool {
        get { object(forKey: Self.hideOnScreenShareKey) as? Bool ?? false }
        set { set(newValue, forKey: Self.hideOnScreenShareKey) }
    }
}
