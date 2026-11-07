import Foundation

/// Polls the wall clock once a minute and reports it as minutes-since-midnight — there's no
/// event-based signal for "the clock just crossed a configured time," so this is the time-based
/// counterpart to `MediaPlaybackMonitor`'s own CoreAudio poll (same `Timer` + `RunLoop.main`
/// pattern, same file's own doc comment on why polling, not a listener, is used). A 60s interval is
/// generous enough that a `Timer` paused by App Nap/system sleep and resumed later still only ever
/// misses a boundary crossing by at most a minute — acceptable for a "quiet hours" feature that
/// isn't claiming second-level precision — and avoids `ScheduledQuietHoursCoordinator` being asked
/// to re-decide dozens of times a minute for no reason.
final class ScheduledQuietHoursWatcher {
    private var pollTimer: Timer?
    var onCheck: ((_ nowMinutes: Int) -> Void)?

    func start() {
        check()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func check() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        onCheck?(nowMinutes)
    }
}
