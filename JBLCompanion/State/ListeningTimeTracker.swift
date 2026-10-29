import Foundation

/// Persists today's accumulated listening seconds + which day they belong to — same plain-string
/// `UserDefaults` convention `IslandSettings.swift` uses (not `HeadphoneState`'s own
/// `"com.davidejere.Hush.*"` namespacing, since this isn't a `HeadphoneState` property).
enum ListeningTimeStore {
    enum Key {
        static let secondsToday = "listeningTimeSecondsToday"
        static let lastRecordedDay = "listeningTimeLastRecordedDay"
    }

    static func secondsToday() -> TimeInterval {
        UserDefaults.standard.double(forKey: Key.secondsToday)
    }

    static func setSecondsToday(_ seconds: TimeInterval) {
        UserDefaults.standard.set(seconds, forKey: Key.secondsToday)
    }

    /// `nil` means "never recorded" — the very first launch, or `UserDefaults` was cleared.
    static func lastRecordedDay() -> String? {
        UserDefaults.standard.string(forKey: Key.lastRecordedDay)
    }

    static func setLastRecordedDay(_ day: String) {
        UserDefaults.standard.set(day, forKey: Key.lastRecordedDay)
    }
}

/// Tracks total seconds-per-day where media is playing AND the headphones are connected at the
/// same time — owner spec, 2026-10-28: "media playing while connected," not mere connect time, so
/// idle silence while just worn doesn't count as "listening."
///
/// Edge-triggered, not polled: `setListening(_:at:)` is meant to be called only when the combined
/// `isMediaPlaying && connection == .connected` condition actually changes (every
/// `AppDelegate` call site that sets either of those two `HeadphoneState` properties recomputes
/// the combined condition and calls this) — it accumulates the elapsed interval between a `true`
/// and the next `false` rather than ticking a timer every second.
final class ListeningTimeTracker {
    private let now: () -> Date
    private let calendar: Calendar
    private var listeningStartedAt: Date?
    private(set) var todaySeconds: TimeInterval

    init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        let today = Self.dayKey(for: now(), calendar: calendar)
        if ListeningTimeStore.lastRecordedDay() == today {
            todaySeconds = ListeningTimeStore.secondsToday()
        } else {
            todaySeconds = 0
            ListeningTimeStore.setSecondsToday(0)
            ListeningTimeStore.setLastRecordedDay(today)
        }
    }

    /// Call exactly when the combined "media playing while connected" condition changes.
    func setListening(_ isListening: Bool, at date: Date? = nil) {
        let date = date ?? now()
        resetIfNewDay(at: date)
        if isListening {
            guard listeningStartedAt == nil else { return } // already listening — no-op
            listeningStartedAt = date
        } else {
            guard let startedAt = listeningStartedAt else { return } // already stopped — no-op
            listeningStartedAt = nil
            todaySeconds += max(0, date.timeIntervalSince(startedAt))
            ListeningTimeStore.setSecondsToday(todaySeconds)
        }
    }

    /// `todaySeconds` plus whatever's elapsed in an in-progress session, if one is active —
    /// what the UI should actually display, so a long listening session shows up live (refreshed
    /// on every call, e.g. from a periodic `TimelineView`) rather than only updating once the
    /// session ends.
    func currentTotalSeconds(at date: Date? = nil) -> TimeInterval {
        let date = date ?? now()
        resetIfNewDay(at: date)
        guard let listeningStartedAt else { return todaySeconds }
        return todaySeconds + max(0, date.timeIntervalSince(listeningStartedAt))
    }

    /// A session actively spanning midnight (app left running overnight while playing) isn't
    /// split precisely at the boundary — the in-progress session's start just moves to `date`,
    /// crediting the rest of it to the new day rather than the old one. A nice-to-have glance
    /// stat, not billing-grade accuracy; precise midnight splitting isn't worth the complexity.
    private func resetIfNewDay(at date: Date) {
        let day = Self.dayKey(for: date, calendar: calendar)
        guard ListeningTimeStore.lastRecordedDay() != day else { return }
        todaySeconds = 0
        if listeningStartedAt != nil { listeningStartedAt = date }
        ListeningTimeStore.setLastRecordedDay(day)
        ListeningTimeStore.setSecondsToday(0)
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
