import Foundation

/// Names and icons the user has given their display setups, such as "Office"
/// with a briefcase for "Built-in Retina Display + DELL U2719D", keyed by
/// `DisplayConfiguration.key`.
///
/// Only the display: saved layout files keep the name macOS reported when
/// they were saved (`Preset.categoryLabel`), so clearing a custom name brings
/// the detected one back.
enum DisplaySetupNames {
    private static let defaultsKey = "displaySetupNames"
    private static let symbolsKey = "displaySetupSymbols"

    /// The icons a display setup can use: SF Symbols available on macOS 14.
    static let symbolChoices: [(symbol: String, name: String)] = [
        ("laptopcomputer", "Laptop"),
        ("display", "Display"),
        ("display.2", "Two displays"),
        ("desktopcomputer", "Desktop computer"),
        ("tv", "TV"),
        ("house", "Home"),
        ("building.2", "Office"),
        ("briefcase", "Work"),
        ("graduationcap", "School"),
        ("book", "Study"),
        ("cup.and.saucer", "Café"),
        ("airplane", "Travel"),
        ("sofa", "Sofa"),
        ("bed.double", "Bedroom"),
        ("moon", "Evening"),
        ("sun.max", "Daytime"),
        ("gamecontroller", "Games"),
        ("paintbrush", "Creative"),
        ("hammer", "Workshop"),
        ("star", "Favourite"),
    ]

    static func all() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    static func name(forKey key: String) -> String? {
        all()[key]
    }

    /// Empty or whitespace clears the custom name.
    static func setName(_ name: String?, forKey key: String) {
        var names = all()
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        names[key] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(names, forKey: defaultsKey)
    }

    static func allSymbols() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: symbolsKey) as? [String: String] ?? [:]
    }

    static func symbol(forKey key: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: symbolsKey) as? [String: String])?[key]
    }

    /// Nil goes back to the default icon.
    static func setSymbol(_ symbol: String?, forKey key: String) {
        var symbols = UserDefaults.standard.dictionary(forKey: symbolsKey) as? [String: String] ?? [:]
        symbols[key] = symbol
        UserDefaults.standard.set(symbols, forKey: symbolsKey)
    }

    /// Two displays or more, or a laptop on its own. The key lists one UUID
    /// per attached display, so its length says how many there are.
    static func defaultSymbol(forKey key: String) -> String {
        key.split(separator: "|").count > 1 ? "display.2" : "laptopcomputer"
    }

    /// The icon to draw for a display setup.
    static func resolvedSymbol(forKey key: String) -> String {
        symbol(forKey: key) ?? defaultSymbol(forKey: key)
    }
}

extension DisplayConfiguration {
    /// What the interface calls this display setup: the user's name for it,
    /// or the one built from the display names.
    var displayName: String { DisplaySetupNames.name(forKey: key) ?? label }
    /// This display setup's icon: the user's choice or the default.
    var displaySymbol: String { DisplaySetupNames.resolvedSymbol(forKey: key) }
}

extension Preset {
    /// What the interface calls the display setup this layout belongs to.
    var displaySetupName: String { DisplaySetupNames.name(forKey: categoryKey) ?? categoryLabel }
}
