import Foundation

/// Pure decision logic for the "DND → ANC" Focus Filter (owner spec, 2026-10-29: "if i turn on
/// dnd, it goes to noise cancellation") — framework-free and testable on its own, same reasoning
/// `NoiseModeRequestCoordinator`'s own split from its AppDelegate wiring follows. `ANCFocusFilterIntent`
/// (the actual `SetFocusFilterIntent` conformance, which needs `AppIntents`/`AppKit` and isn't
/// unit-testable the same way) calls into this via `AppDelegate.applyFocusFilterANC(active:)`.
///
/// While the Focus is active: switches to ANC and remembers whatever mode was active before, so
/// it can be restored rather than left on ANC permanently once the Focus turns off again.
final class FocusFilterNoiseModeCoordinator {
    private(set) var savedModeBeforeFilter: CommandableNoiseMode?

    /// `isActive`: whether the Focus this filter is attached to just turned on (`true`) or off
    /// (`false` — `SetFocusFilterIntent`'s own documented "parameter is `nil`" deactivation
    /// signal, already resolved to a plain `Bool` by the caller). `currentMode`: the noise mode
    /// in effect right now, only consulted on activation (so it's `nil`-safe for the caller to
    /// pass whatever default makes sense when nothing's been reported yet).
    ///
    /// Returns the noise mode that should actually be requested, or `nil` when there's nothing to
    /// do — activating while already active (don't stomp the already-saved "before" mode with
    /// whatever ANC itself reports), or deactivating with nothing saved (this filter was never
    /// actually the one that turned ANC on, e.g. the app relaunched mid-Focus and lost its saved
    /// state — restoring an arbitrary mode in that case would be a surprise, not a restore).
    func modeToRequest(whenFocusActive isActive: Bool, currentMode: CommandableNoiseMode) -> CommandableNoiseMode? {
        if isActive {
            guard savedModeBeforeFilter == nil else { return nil }
            savedModeBeforeFilter = currentMode
            return .anc
        } else {
            guard let saved = savedModeBeforeFilter else { return nil }
            savedModeBeforeFilter = nil
            return saved
        }
    }
}
