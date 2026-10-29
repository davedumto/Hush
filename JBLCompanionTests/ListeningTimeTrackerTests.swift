import XCTest
@testable import JBLCompanion

/// `ListeningTimeTracker` persists through `ListeningTimeStore`'s own global (not per-display-UUID)
/// `UserDefaults.standard` keys — the exact same shape of real-key pollution risk
/// `IslandSettingsTests`'s own `autoExpandOnConnect` tests were built to avoid (that file's own doc
/// comment has the full story: a real toggle on the developer's own machine silently reset on
/// every `xcodebuild test` run before the snapshot/restore fix). Snapshotting both keys here before
/// each test and restoring them exactly afterward makes this suite free to mutate during a test
/// with zero observable effect on real app state once it ends.
final class ListeningTimeTrackerTests: XCTestCase {
    private var savedSecondsToday: Any?
    private var savedLastRecordedDay: Any?

    override func setUp() {
        super.setUp()
        savedSecondsToday = UserDefaults.standard.object(forKey: ListeningTimeStore.Key.secondsToday)
        savedLastRecordedDay = UserDefaults.standard.object(forKey: ListeningTimeStore.Key.lastRecordedDay)
    }

    override func tearDown() {
        restore(savedSecondsToday, forKey: ListeningTimeStore.Key.secondsToday)
        restore(savedLastRecordedDay, forKey: ListeningTimeStore.Key.lastRecordedDay)
        super.tearDown()
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)!
    }

    // MARK: - Accumulation

    func testAccumulatesWhileListening() {
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 10:00:00") }, calendar: utcCalendar())
        tracker.setListening(true, at: date("2026-10-28 10:00:00"))
        tracker.setListening(false, at: date("2026-10-28 10:05:00"))
        XCTAssertEqual(tracker.todaySeconds, 300, accuracy: 0.001)
    }

    func testDoesNotAccumulateWithoutAListeningSession() {
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 10:00:00") }, calendar: utcCalendar())
        XCTAssertEqual(tracker.todaySeconds, 0)
    }

    func testRedundantSetListeningTrueDoesNotResetTheSessionStart() {
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 10:00:00") }, calendar: utcCalendar())
        tracker.setListening(true, at: date("2026-10-28 10:00:00"))
        tracker.setListening(true, at: date("2026-10-28 10:10:00")) // no-op — already listening
        tracker.setListening(false, at: date("2026-10-28 10:20:00"))
        XCTAssertEqual(tracker.todaySeconds, 20 * 60, accuracy: 0.001)
    }

    func testRedundantSetListeningFalseIsANoOp() {
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 10:00:00") }, calendar: utcCalendar())
        tracker.setListening(false, at: date("2026-10-28 10:00:00")) // never started — no-op
        XCTAssertEqual(tracker.todaySeconds, 0)
    }

    // MARK: - Live, in-progress session

    func testCurrentTotalSecondsIncludesAnInProgressSession() {
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 10:00:00") }, calendar: utcCalendar())
        tracker.setListening(true, at: date("2026-10-28 10:00:00"))
        XCTAssertEqual(tracker.currentTotalSeconds(at: date("2026-10-28 10:02:00")), 120, accuracy: 0.001)
        // The persisted/completed-only total stays 0 until the session actually ends.
        XCTAssertEqual(tracker.todaySeconds, 0)
    }

    func testCurrentTotalSecondsWithNoActiveSessionMatchesTodaySeconds() {
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 10:00:00") }, calendar: utcCalendar())
        tracker.setListening(true, at: date("2026-10-28 10:00:00"))
        tracker.setListening(false, at: date("2026-10-28 10:05:00"))
        XCTAssertEqual(tracker.currentTotalSeconds(at: date("2026-10-28 10:30:00")), tracker.todaySeconds, accuracy: 0.001)
    }

    // MARK: - Day rollover

    func testResetsAtDayRollover() {
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 23:00:00") }, calendar: utcCalendar())
        tracker.setListening(true, at: date("2026-10-28 23:00:00"))
        tracker.setListening(false, at: date("2026-10-28 23:30:00"))
        XCTAssertEqual(tracker.todaySeconds, 30 * 60, accuracy: 0.001)

        tracker.setListening(true, at: date("2026-10-29 00:05:00")) // a new day — no stale carryover
        XCTAssertEqual(tracker.todaySeconds, 0)
    }

    func testCurrentTotalSecondsAlsoRollsOverAtMidnightEvenWithNoSetListeningCall() {
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 23:00:00") }, calendar: utcCalendar())
        tracker.setListening(true, at: date("2026-10-28 23:00:00"))
        tracker.setListening(false, at: date("2026-10-28 23:30:00"))
        // Just reading the total after midnight, with no intervening setListening call, must
        // still see the reset — a UI that only ever reads (never writes) shouldn't see yesterday's
        // total persist into the new day.
        XCTAssertEqual(tracker.currentTotalSeconds(at: date("2026-10-29 06:00:00")), 0, accuracy: 0.001)
    }

    // MARK: - Persistence round-trip

    func testLoadsAPersistedTotalFromTheSameDay() {
        ListeningTimeStore.setLastRecordedDay("2026-10-28")
        ListeningTimeStore.setSecondsToday(600)
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 09:00:00") }, calendar: utcCalendar())
        XCTAssertEqual(tracker.todaySeconds, 600, accuracy: 0.001)
    }

    func testDiscardsAPersistedTotalFromADifferentDay() {
        ListeningTimeStore.setLastRecordedDay("2026-10-27")
        ListeningTimeStore.setSecondsToday(600)
        let tracker = ListeningTimeTracker(now: { self.date("2026-10-28 09:00:00") }, calendar: utcCalendar())
        XCTAssertEqual(tracker.todaySeconds, 0)
    }
}
