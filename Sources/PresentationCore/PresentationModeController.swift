/// A coverable surface for one screen. The app backs this with an NSWindow; the
/// controller stays AppKit-free so it can be unit-tested.
public protocol DesktopOverlay: AnyObject {
    func present()
    func dismiss()
}

/// Owns the hide/show state and the per-screen overlay lifecycle. Generic over
/// the screen type so tests use a fake; the app uses `NSScreen`.
public final class PresentationModeController<Screen> {
    public private(set) var isHidden = false

    private var overlays: [DesktopOverlay] = []
    private let screens: () -> [Screen]
    private let makeOverlay: (Screen) -> DesktopOverlay

    public init(screens: @escaping () -> [Screen],
                makeOverlay: @escaping (Screen) -> DesktopOverlay) {
        self.screens = screens
        self.makeOverlay = makeOverlay
    }

    public func hide() {
        guard !isHidden else { return }
        overlays = screens().map(makeOverlay)
        overlays.forEach { $0.present() }
        isHidden = true
    }

    public func show() {
        overlays.forEach { $0.dismiss() }
        overlays.removeAll()
        isHidden = false
    }

    public func toggle() { isHidden ? show() : hide() }

    /// Recreate the overlay set for the current screens and what they show,
    /// but only while hidden: after a screen-configuration change, or a
    /// switch to a Space with a different wallpaper. The new overlays go up
    /// before the old ones come down, so the icons never show in between.
    public func rebuildIfHidden() {
        guard isHidden else { return }
        let old = overlays
        overlays = screens().map(makeOverlay)
        overlays.forEach { $0.present() }
        old.forEach { $0.dismiss() }
    }
}
