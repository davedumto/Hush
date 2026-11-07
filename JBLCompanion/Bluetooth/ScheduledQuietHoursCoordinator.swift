import Foundation

/// Pure decision logic for "quiet hours" (owner spec, 2026-11-07, feature brainstorm #3: "scheduled
/// noise mode — 'quiet hours' that switch to ANC/Off at set times, independent of Focus") —
/// framework-free and testable on its own, same split as `FocusFilterNoiseModeCoordinator`'s own
/// doc comment describes for the DND → ANC feature. Same save/restore shape as that coordinator too:
/// entering the window remembers whatever mode was active so it can be restored on exit, rather than
/// left on the quiet-hours mode permanently.
///
/// Time is passed in as plain minutes-since-midnight (0...1439), not `Date`/`Calendar` — the caller
/// (`ScheduledQuietHoursWatcher`) owns turning a real clock reading into that number; keeping this
/// class itself free of `Date`/`Calendar`/timezone concerns is what makes `isWithinWindow` trivial
/// to test exhaustively, including the overnight-wrap case (e.g. 22:00 → 07:00, where the numeric
/// start is *larger* than the end).
final class ScheduledQuietHoursCoordinator {
    private(set) var savedModeBeforeQuietHours: CommandableNoiseMode?

    /// A zero-length window (`startMinutes == endMinutes`) is never active — distinguishes "the
    /// user hasn't set a real window yet" from "the window spans the whole day," which this
    /// representation can't otherwise express (and the owner's own feature framing — "set times,"
    /// a bounded window — never implied an always-on option).
    static func isWithinWindow(nowMinutes: Int, startMinutes: Int, endMinutes: Int) -> Bool {
        guard startMinutes != endMinutes else { return false }
        if startMinutes < endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            // Wraps past midnight (e.g. 22:00 → 07:00): "within window" means at/after start OR
            // before end, not a single contiguous numeric range.
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }

    /// Returns the noise mode that should actually be requested, or `nil` when there's nothing to
    /// do — same "don't stomp an already-saved mode" / "nothing to restore" guards as
    /// `FocusFilterNoiseModeCoordinator.modeToRequest(whenFocusActive:currentMode:)`.
    func modeToRequest(
        nowMinutes: Int, startMinutes: Int, endMinutes: Int, quietHoursMode: CommandableNoiseMode,
        currentMode: CommandableNoiseMode
    ) -> CommandableNoiseMode? {
        let shouldBeActive = Self.isWithinWindow(nowMinutes: nowMinutes, startMinutes: startMinutes, endMinutes: endMinutes)
        if shouldBeActive {
            guard savedModeBeforeQuietHours == nil else { return nil }
            savedModeBeforeQuietHours = currentMode
            return quietHoursMode
        } else {
            guard let saved = savedModeBeforeQuietHours else { return nil }
            savedModeBeforeQuietHours = nil
            return saved
        }
    }
}
