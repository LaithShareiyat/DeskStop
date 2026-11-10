import AppKit

/// Light, dark, or whatever macOS is set to. Applies to every window the app
/// shows, the menu bar panel included.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// nil follows macOS.
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Applies the stored choice to the whole app.
    static func applyStored() {
        NSApp.appearance = UserDefaults.standard.appearanceMode.appearance
    }

    /// For the menu bar panel. A popover takes its appearance from the status
    /// item's window, which follows macOS rather than `NSApp.appearance`, so
    /// it is given one explicitly, the system's own when set to System.
    static var panelAppearance: NSAppearance? {
        if let chosen = UserDefaults.standard.appearanceMode.appearance { return chosen }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}

extension UserDefaults {
    private static let appearanceModeKey = "appearanceMode"

    var appearanceMode: AppearanceMode {
        get { string(forKey: Self.appearanceModeKey).flatMap(AppearanceMode.init(rawValue:)) ?? .system }
        set { set(newValue.rawValue, forKey: Self.appearanceModeKey) }
    }
}
