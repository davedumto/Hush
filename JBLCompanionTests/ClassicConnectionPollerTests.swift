import XCTest
@testable import JBLCompanion

@MainActor
final class ClassicConnectionPollerTests: XCTestCase {
    /// `fireNextCheck` runs the oldest still-scheduled check (FIFO, matching how a real timer
    /// queue would fire them) and reports whether there was one to run, along with the delay it
    /// was scheduled with (so a test can assert the fast-vs-slow interval actually used).
    private func makePoller(
        isConnected: @escaping () -> Bool, onConnected: @escaping (String) -> Void
    ) -> (poller: ClassicConnectionPoller, fireNextCheck: () -> TimeInterval?) {
        var scheduled: [(delay: TimeInterval, callback: () -> Void)] = []
        let poller = ClassicConnectionPoller(
            checkIsConnected: isConnected,
            scheduleCheck: { delay, callback in scheduled.append((delay, callback)) },
            onConnected: onConnected
        )
        let fireNextCheck: () -> TimeInterval? = {
            guard !scheduled.isEmpty else { return nil }
            let next = scheduled.removeFirst()
            next.callback()
            return next.delay
        }
        return (poller, fireNextCheck)
    }

    // MARK: - Already connected when polling starts

    func testInitialStateConnectedFiresOnTheFirstCheckAfterWarmUp() {
        var reportedSources: [String] = []
        let (poller, fireNextCheck) = makePoller(
            isConnected: { true },
            onConnected: { source in reportedSources.append(source) }
        )

        poller.start()
        let delay = fireNextCheck()

        XCTAssertEqual(delay, ClassicConnectionPoller.warmUpDelay)
        XCTAssertEqual(reportedSources, ["initial poll"])
        XCTAssertNil(fireNextCheck(), "no further check should be scheduled once connected")
    }

    // MARK: - Not connected yet, becomes connected later

    func testLateConnectIsCaughtByAFollowUpPoll() {
        var connected = false
        var reportedSources: [String] = []
        let (poller, fireNextCheck) = makePoller(
            isConnected: { connected },
            onConnected: { source in reportedSources.append(source) }
        )

        poller.start()
        XCTAssertEqual(fireNextCheck(), ClassicConnectionPoller.warmUpDelay) // not connected yet
        XCTAssertTrue(reportedSources.isEmpty)

        connected = true
        XCTAssertEqual(fireNextCheck(), ClassicConnectionPoller.fastPollInterval) // now it is
        XCTAssertEqual(reportedSources, ["poll timer"])
    }

    func testFastPollingSwitchesToSlowPollingAfterTheFastWindow() {
        var reportedSources: [String] = []
        let (poller, fireNextCheck) = makePoller(
            isConnected: { false },
            onConnected: { source in reportedSources.append(source) }
        )

        poller.start()
        // warmUpDelay(2) then fastPollInterval(3) repeated: elapsed reaches 2,5,8,...,29 — all
        // still under the 30s fast-poll window, so every one of these ten checks should be fast.
        XCTAssertEqual(fireNextCheck(), ClassicConnectionPoller.warmUpDelay) // elapsed = 2
        for _ in 0..<9 {
            XCTAssertEqual(fireNextCheck(), ClassicConnectionPoller.fastPollInterval)
        } // elapsed now 2 + 9*3 = 29, still under the 30s window

        // The next check pushes elapsed to 32, past the window — so the one scheduled after *that*
        // check should use the slow interval.
        XCTAssertEqual(fireNextCheck(), ClassicConnectionPoller.fastPollInterval) // elapsed = 32
        XCTAssertEqual(fireNextCheck(), ClassicConnectionPoller.slowPollInterval)

        XCTAssertTrue(reportedSources.isEmpty, "isConnected never returned true in this test")
    }

    // MARK: - stop() cancels a pending check

    func testStopCancelsAPendingCheck() {
        var reportedSources: [String] = []
        let (poller, fireNextCheck) = makePoller(
            isConnected: { true },
            onConnected: { source in reportedSources.append(source) }
        )

        poller.start()
        poller.stop()
        _ = fireNextCheck() // the warm-up check fires late, after stop()

        XCTAssertTrue(reportedSources.isEmpty, "a check scheduled before stop() must not report connected afterward")
    }

    func testRestartingResetsTheScheduleFromTheWarmUpDelay() {
        var reportedSources: [String] = []
        let (poller, fireNextCheck) = makePoller(
            isConnected: { false },
            onConnected: { source in reportedSources.append(source) }
        )

        poller.start()
        _ = fireNextCheck() // warm-up, not connected — schedules the next (fast-poll) check

        poller.start() // restart, e.g. after a disconnect-then-reconnect cycle, before that
        // fast-poll check ever fires. A real timer would still fire it, harmlessly — the
        // generation bump inside start() makes it a no-op — so this fake queue (FIFO, like a
        // real one) still has it ahead of the fresh schedule start() just queued. Fire and
        // discard it, same as a real stale timer firing late, before checking the live schedule.
        _ = fireNextCheck()

        XCTAssertEqual(fireNextCheck(), ClassicConnectionPoller.warmUpDelay)
    }
}
