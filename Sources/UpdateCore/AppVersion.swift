import Foundation

/// A dotted release version such as `1.4.2`, parsed from a bundle version or a
/// git tag (`v1.4.2`). A pre-release suffix (`1.5.0-beta.1`) sorts before the
/// release it precedes, so a beta user is still offered the final build.
public struct AppVersion: Comparable, CustomStringConvertible {
    public let components: [Int]
    public let prerelease: String?

    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        let parts = text.split(separator: "-", maxSplits: 1).map(String.init)
        guard let core = parts.first, !core.isEmpty else { return nil }
        var numbers: [Int] = []
        for piece in core.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(piece), n >= 0 else { return nil }
            numbers.append(n)
        }
        components = numbers
        prerelease = parts.count > 1 ? parts[1] : nil
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
            + (prerelease.map { "-\($0)" } ?? "")
    }

    /// `1.2` and `1.2.0` are the same version.
    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        compareCore(a, b) == .orderedSame && a.prerelease == b.prerelease
    }

    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        switch compareCore(a, b) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame:
            switch (a.prerelease, b.prerelease) {
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
            }
        }
    }

    private static func compareCore(_ a: AppVersion, _ b: AppVersion) -> ComparisonResult {
        let count = max(a.components.count, b.components.count)
        for i in 0..<count {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
