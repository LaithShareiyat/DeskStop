import Foundation

/// A deadline after which display-change events are interesting again.
///
/// Applying a display arrangement itself posts screen-parameter change
/// notifications, which the monitor would debounce into an `onChange` and
/// re-trigger the restore that caused them. This is the first layer of that
/// defence; the second is the already-correct short-circuit in
/// `ArrangementPolicy`.
/// slower hardware.
public struct SuppressionWindow {
    private var until: Date?

    public init() {}

    /// Extend suppression to `date`. An earlier deadline never shortens an
    /// active window, so overlapping applies cannot cut each other short.
    public mutating func suppress(until date: Date) {
        if let current = until, current > date { return }
        until = date
    }

    public func isSuppressed(now: Date) -> Bool {
        guard let until else { return false }
        return now < until
    }
}
