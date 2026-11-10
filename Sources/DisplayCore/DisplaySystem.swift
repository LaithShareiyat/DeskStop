import Foundation

/// The platform boundary for reading and writing the display layout.
///
/// Injected so `ArrangementPolicy` — which owns every risky decision — can be
/// driven through all of its branches by a fake. The real implementation lives
/// in the app target and wraps the CoreGraphics display configuration APIs.
public protocol DisplaySystem {
    /// Every currently attached display, where it sits (CG global
    /// coordinates) and its current mode. The set of attached UUIDs is
    /// derived from this.
    func currentPlacements() -> [DisplayArrangement.Placement]

    /// Every mode the display can be set to right now, sharp (HiDPI) scaled
    /// modes included. Empty for a display that isn't attached.
    func availableModes(forDisplay uuid: String) -> [DisplayMode]

    /// Move the displays in `origins` and set the modes in `modes` (by
    /// display UUID), as one transaction. Displays not named are left as
    /// they are; a placement's own `mode` is ignored here. Throws if the
    /// transaction could not be opened, configured, or committed.
    func apply(origins: [DisplayArrangement.Placement], modes: [String: DisplayMode]) throws
}
