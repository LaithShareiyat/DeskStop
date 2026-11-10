import Foundation
import SchedulingCore

/// Persists all schedules in a single `schedules.json` under Application Support.
/// Posts `didChangeNotification` after every mutation so the Scheduler re-arms
/// and any open window refreshes.
final class ScheduleStore {
    static let didChangeNotification = Notification.Name("DeskStop.SchedulesDidChange")

    private let fileURL: URL

    init() {
        let dir = DataFolder.ensured()
        fileURL = dir.appendingPathComponent("schedules.json")
    }

    func load() -> [Schedule] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let entries = try? JSONDecoder().decode([Failable<Schedule>].self, from: data) else { return [] }
        return entries.compactMap { $0.value }
    }

    func saveAll(_ schedules: [Schedule]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(schedules)
            // .atomic: a crash or full disk mid-write must not leave a
            // truncated file — load() would return [] and the next mutation
            // would persist that emptiness, destroying every schedule.
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("DeskStop: failed to write schedules.json — changes were not persisted: \(error)")
        }
        // Post even after a failed write: observers reload from disk, so the
        // UI snaps back to the last persisted state instead of showing a
        // phantom edit.
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    func add(_ schedule: Schedule) {
        var all = load(); all.append(schedule); saveAll(all)
    }

    func update(_ schedule: Schedule) {
        var all = load()
        if let i = all.firstIndex(where: { $0.id == schedule.id }) {
            all[i] = schedule
        } else {
            all.append(schedule)
        }
        saveAll(all)
    }

    func delete(id: UUID) {
        saveAll(load().filter { $0.id != id })
    }

    func setEnabled(id: UUID, _ enabled: Bool) {
        var all = load()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].enabled = enabled
        saveAll(all)
    }
}

/// Decodes each array element independently; a malformed entry becomes nil
/// instead of failing the whole decode.
private struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
