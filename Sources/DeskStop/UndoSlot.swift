import Foundation
import DisplayCore

/// The desktop arrangement that a restore displaced, so it can be brought back.
struct UndoSnapshot: Codable {
    let positions: [IconPosition]
    /// Display-configuration key the snapshot belongs to; undo is only offered
    /// while the same display setup is active.
    let categoryKey: String
    let takenAt: Date
    /// Name of the preset whose restore displaced this arrangement.
    let displacedBy: String
    /// Display layout in effect before the restore; nil if the restore left it alone.
    let displayArrangement: DisplayArrangement?
}

/// Single-level undo for restores, persisted so it survives relaunch. Before
/// any restore rearranges the desktop, the current arrangement is stashed
/// here; Undo Last Restore swaps it back (stashing what it replaces, so
/// invoking undo twice toggles between the two arrangements).
final class UndoSlotStore {
    private let fileURL: URL
    /// In-memory copy; this store is the file's only writer, so the cache is
    /// authoritative after first read. The snapshot holds every icon's
    /// position — re-decoding it on each menu rebuild would be wasted I/O.
    private var cache: UndoSnapshot??

    init() {
        let dir = DataFolder.ensured()
        fileURL = dir.appendingPathComponent("undo-slot.json")
    }

    func load() -> UndoSnapshot? {
        if let cached = cache { return cached }
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode(UndoSnapshot.self, from: $0) }
        cache = .some(loaded)
        return loaded
    }

    func save(_ snapshot: UndoSnapshot) {
        cache = .some(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("DeskStop: failed to write undo slot: \(error)")
        }
    }

    /// Snapshot the live desktop into the slot, recording which preset's
    /// restore is about to displace it. Failures are silent — losing an undo
    /// point must never block the restore itself.
    func stashCurrentArrangement(displacedBy presetName: String,
                                 categoryKey: String,
                                 displayArrangement: DisplayArrangement? = nil) {
        guard let snap = try? IconArrangement.snapshot(), !snap.positions.isEmpty else { return }
        save(UndoSnapshot(positions: snap.positions,
                          categoryKey: categoryKey,
                          takenAt: Date(),
                          displacedBy: presetName,
                          displayArrangement: displayArrangement))
    }
}
