import XCTest
@testable import JBLCompanion

@MainActor
final class RFCOMMOpenRetryCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        attemptOpen: @escaping () -> Void
    ) -> (coordinator: RFCOMMOpenRetryCoordinator, fireNextRetry: () -> Bool) {
        var scheduled: [() -> Void] = []
        let coordinator = RFCOMMOpenRetryCoordinator(
            scheduleRetry: { callback in scheduled.append(callback) },
            attemptOpen: attemptOpen
        )
        let fireNextRetry: () -> Bool = {
            guard !scheduled.isEmpty else { return false }
            scheduled.removeFirst()()
            return true
        }
        return (coordinator, fireNextRetry)
    }

    func testStartAttemptsImmediately() {
        var attemptCount = 0
        let (coordinator, _) = makeCoordinator(attemptOpen: { attemptCount += 1 })

        coordinator.start()

        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(coordinator.retryCount, 0)
    }

    func testFailureSchedulesARetry() {
        var attemptCount = 0
        let (coordinator, fireNextRetry) = makeCoordinator(attemptOpen: { attemptCount += 1 })

        coordinator.start()
        coordinator.handleOpenFailure()
        XCTAssertTrue(fireNextRetry())

        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(coordinator.retryCount, 1)
    }

    func testSuccessStopsRetryingAndResetsCount() {
        var attemptCount = 0
        let (coordinator, fireNextRetry) = makeCoordinator(attemptOpen: { attemptCount += 1 })

        coordinator.start()
        coordinator.handleOpenFailure()
        XCTAssertTrue(fireNextRetry()) // retry attempt 1
        coordinator.handleOpenSuccess()

        XCTAssertEqual(coordinator.retryCount, 0)
        XCTAssertEqual(attemptCount, 2)
    }

    // MARK: - Retry exhaustion

    func testNeverRetriesMoreThanThreeTimes() {
        var attemptCount = 0
        let (coordinator, fireNextRetry) = makeCoordinator(attemptOpen: { attemptCount += 1 })

        coordinator.start() // attempt 1 (not a "retry")
        for _ in 0..<RFCOMMOpenRetryCoordinator.maxRetries {
            coordinator.handleOpenFailure()
            XCTAssertTrue(fireNextRetry())
        }
        // The 3rd retry's own failure must not schedule a 4th.
        coordinator.handleOpenFailure()
        XCTAssertFalse(fireNextRetry())

        XCTAssertEqual(coordinator.retryCount, RFCOMMOpenRetryCoordinator.maxRetries)
        XCTAssertEqual(attemptCount, 1 + RFCOMMOpenRetryCoordinator.maxRetries) // 1 initial + 3 retries
    }

    // MARK: - Disconnect cancels a pending retry

    func testCancelStopsAPendingRetryFromFiringLate() {
        var attemptCount = 0
        let (coordinator, fireNextRetry) = makeCoordinator(attemptOpen: { attemptCount += 1 })

        coordinator.start() // attempt 1
        coordinator.handleOpenFailure() // schedules retry 1

        coordinator.cancel() // e.g. classic disconnected before the retry timer fires

        XCTAssertTrue(fireNextRetry(), "the timer itself still fires late")
        XCTAssertEqual(attemptCount, 1, "but it must not call attemptOpen again after cancel()")
    }

    func testStartAfterCancelBeginsARetryCountFreshAndFiresImmediately() {
        var attemptCount = 0
        let (coordinator, fireNextRetry) = makeCoordinator(attemptOpen: { attemptCount += 1 })

        coordinator.start()
        coordinator.handleOpenFailure()
        XCTAssertTrue(fireNextRetry()) // retryCount == 1
        XCTAssertEqual(coordinator.retryCount, 1)

        coordinator.cancel()
        coordinator.start() // a fresh connection attempt, e.g. after reconnecting

        XCTAssertEqual(coordinator.retryCount, 0)
        XCTAssertEqual(attemptCount, 3) // start, retry 1, fresh start
    }
}
