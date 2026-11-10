import Foundation

/// The order the user has put each display setup's layouts in, set by dragging
/// them in Settings → Layouts, stored as layout ids per setup key. Layouts not
/// in the stored order follow the ordered ones, alphabetically.
///
/// Used wherever a setup's layouts are listed, and by Restore Next Layout.
enum LayoutOrder {
    private static let defaultsKey = "layoutOrder"

    private static func all() -> [String: [String]] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [String]] ?? [:]
    }

    /// `presets` sorted into the stored order for `setupKey`.
    static func sorted(_ presets: [Preset], forSetup setupKey: String) -> [Preset] {
        let order = all()[setupKey] ?? []
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return presets.sorted { a, b in
            switch (rank[a.id.uuidString], rank[b.id.uuidString]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    /// Moves `id` to sit just before `target`, or to the end when `target` is
    /// nil. `current` is the setup's layouts in the order shown now, which
    /// becomes the stored order.
    static func move(_ id: UUID, before target: UUID?, in current: [UUID], forSetup setupKey: String) {
        guard id != target, current.contains(id) else { return }
        var ids = current.filter { $0 != id }
        if let target, let index = ids.firstIndex(of: target) {
            ids.insert(id, at: index)
        } else {
            ids.append(id)
        }
        save(ids, forSetup: setupKey)
    }

    /// Moves `id` one place up (-1) or down (+1).
    static func move(_ id: UUID, by offset: Int, in current: [UUID], forSetup setupKey: String) {
        guard let index = current.firstIndex(of: id) else { return }
        let destination = index + offset
        guard current.indices.contains(destination) else { return }
        var ids = current
        ids.swapAt(index, destination)
        save(ids, forSetup: setupKey)
    }

    private static func save(_ ids: [UUID], forSetup setupKey: String) {
        var orders = all()
        orders[setupKey] = ids.map(\.uuidString)
        UserDefaults.standard.set(orders, forKey: defaultsKey)
    }
}
