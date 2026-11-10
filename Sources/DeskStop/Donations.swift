import Foundation

/// Buy Me a Coffee, for Settings → About. DeskStop is free and open source;
/// this is how people can say thanks.
enum Donations {
    /// The part after buymeacoffee.com/. If empty,
    /// the button is hidden; `.github/FUNDING.yml` has the same name.
    static let buyMeACoffeeUsername = "LaithSh"

    static var url: URL? {
        guard !buyMeACoffeeUsername.isEmpty else { return nil }
        return URL(string: "https://www.buymeacoffee.com/\(buyMeACoffeeUsername)")
    }
}
