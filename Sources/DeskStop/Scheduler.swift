import AppKit
import SchedulingCore

/// Owns the single fire timer. Always recomputes the next fire from "now", so
/// occurrences missed while asleep or quit are simply skipped (no catch-up).
final class Scheduler {
    private let store: ScheduleStore
    private let fire: (Schedule) -> Void
    private let calendar: Calendar
    private var timer: Timer?
    /// Last instant we fired, so a slightly-early timer can't double-fire it.
    private var lastFired: Date?

    init(store: ScheduleStore,
         calendar: Calendar = .current,
         fire: @escaping (Schedule) -> Void) {
        self.store = store
        self.calendar = calendar
        self.fire = fire
    }

    func start() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(rearm),
            name: ScheduleStore.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(rearm),
            name: Notification.Name.NSSystemClockDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(rearm),
            name: NSWorkspace.didWakeNotification, object: nil)
        rearm()
    }

    /// The soonest upcoming (schedule, fire date), for display in the menu.
    func nextUpcoming() -> (schedule: Schedule, date: Date)? {
        let schedules = store.load()
        guard let next = ScheduleEngine.nextFire(in: schedules, after: Date(), calendar: calendar),
              let first = next.due.first,
              let schedule = schedules.first(where: { $0.id == first })
        else { return nil }
        return (schedule, next.date)
    }

    @objc func rearm() {
        // Observers can deliver off-main (NSSystemClockDidChange posts on the
        // changing thread); Timer invalidate/add are main-run-loop-only here.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.rearm() }
            return
        }
        timer?.invalidate()
        timer = nil
        let schedules = store.load()
        let after = max(Date(), lastFired ?? .distantPast)
        guard let next = ScheduleEngine.nextFire(in: schedules, after: after, calendar: calendar) else { return }
        let delay = max(0, next.date.timeIntervalSinceNow)
        let due = next.due
        let fireDate = next.date
        // .common mode so the timer still fires while the status-bar menu is
        // open (menu tracking parks the run loop outside the default mode).
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.fireDue(at: fireDate, ids: due)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fireDue(at date: Date, ids: [UUID]) {
        // A timer that came due during sleep is serviced on wake and can win
        // the race against the didWake rearm. Enforce the no-catch-up
        // contract here: if we're firing much later than scheduled, skip the
        // stale occurrence and recompute from now.
        guard Date().timeIntervalSince(date) < 90 else {
            NSLog("DeskStop scheduler: skipping stale fire scheduled for \(date)")
            rearm()
            return
        }
        lastFired = date
        let schedules = store.load()
        for id in ids {
            if let s = schedules.first(where: { $0.id == id }), s.enabled {
                fire(s)
            }
        }
        rearm()
    }
}
