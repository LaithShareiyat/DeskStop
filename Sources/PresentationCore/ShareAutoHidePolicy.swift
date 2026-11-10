/// Decides when screen-share detection should hide or show the desktop icons.
/// Pure state machine — the app layer feeds it one reading per poll tick and
/// applies the returned action to `PresentationModeController`.
///
/// Guarantees:
/// - Only ever shows a desktop it hid itself; a manual hide is never undone.
/// - If the user manually shows the icons mid-share, stays out of the way
///   until that share session fully ends.
/// - Unhiding waits for `unhideThreshold` consecutive share-free polls, so
///   screenshot blips and brief re-shares don't flap the overlays.
/// - Switching the feature off shows what it hid (`stop`), since nothing
///   else would.
public struct ShareAutoHidePolicy {
    public enum Action: Equatable {
        case hide, show, none
    }

    private enum State {
        case idle
        /// We hid the desktop for an active share.
        case autoHidden
        /// User re-showed the desktop mid-share; stand down until it ends.
        case overridden
    }

    private var state: State = .idle
    private var clearPolls = 0
    private let unhideThreshold: Int

    public init(unhideThreshold: Int = 3) {
        self.unhideThreshold = unhideThreshold
    }

    public mutating func tick(sharing: Bool, desktopHidden: Bool) -> Action {
        switch state {
        case .idle:
            if sharing && !desktopHidden {
                state = .autoHidden
                clearPolls = 0
                return .hide
            }
            return .none

        case .autoHidden:
            if !desktopHidden {
                // Someone else showed the desktop (user action, or the app
                // layer skipped our hide) — stop claiming ownership.
                state = sharing ? .overridden : .idle
                clearPolls = 0
                return .none
            }
            if sharing {
                clearPolls = 0
                return .none
            }
            clearPolls += 1
            if clearPolls >= unhideThreshold {
                state = .idle
                clearPolls = 0
                return .show
            }
            return .none

        case .overridden:
            if sharing {
                clearPolls = 0
            } else {
                clearPolls += 1
                if clearPolls >= unhideThreshold {
                    state = .idle
                    clearPolls = 0
                }
            }
            return .none
        }
    }

    /// The feature was switched off, so no more ticks are coming. Shows the
    /// desktop if this policy hid it: otherwise the icons would stay hidden
    /// with nothing left to bring them back. A manual hide stays. Resets, so
    /// switching the feature back on starts fresh.
    public mutating func stop(desktopHidden: Bool) -> Action {
        defer {
            state = .idle
            clearPolls = 0
        }
        if case .autoHidden = state, desktopHidden { return .show }
        return .none
    }
}
