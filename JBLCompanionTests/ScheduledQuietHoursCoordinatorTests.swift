import XCTest
@testable import JBLCompanion

final class ScheduledQuietHoursCoordinatorTests: XCTestCase {
    // MARK: - isWithinWindow (pure logic)

    func testWithinWindowOrdinaryNonWrappingRange() {
        // 09:00 to 17:00 (540...1020)
        XCTAssertFalse(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 539, startMinutes: 540, endMinutes: 1020))
        XCTAssertTrue(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 540, startMinutes: 540, endMinutes: 1020)) // inclusive start
        XCTAssertTrue(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 900, startMinutes: 540, endMinutes: 1020))
        XCTAssertFalse(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 1020, startMinutes: 540, endMinutes: 1020)) // exclusive end
    }

    func testWithinWindowOvernightWrappingRange() {
        // 22:00 to 07:00 (1320...420), spans midnight
        XCTAssertTrue(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 1320, startMinutes: 1320, endMinutes: 420)) // inclusive start
        XCTAssertTrue(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 1439, startMinutes: 1320, endMinutes: 420)) // 23:59
        XCTAssertTrue(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 0, startMinutes: 1320, endMinutes: 420)) // midnight
        XCTAssertTrue(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 419, startMinutes: 1320, endMinutes: 420))
        XCTAssertFalse(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 420, startMinutes: 1320, endMinutes: 420)) // exclusive end
        XCTAssertFalse(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 900, startMinutes: 1320, endMinutes: 420)) // mid-afternoon, outside
    }

    func testZeroLengthWindowIsNeverActive() {
        XCTAssertFalse(ScheduledQuietHoursCoordinator.isWithinWindow(nowMinutes: 600, startMinutes: 600, endMinutes: 600))
    }

    // MARK: - modeToRequest (save/restore state machine)

    func testEnteringWindowSavesCurrentModeAndRequestsConfiguredMode() {
        let coordinator = ScheduledQuietHoursCoordinator()
        let result = coordinator.modeToRequest(
            nowMinutes: 1350, startMinutes: 1320, endMinutes: 420, quietHoursMode: .anc, currentMode: .ambientAware
        )
        XCTAssertEqual(result, .anc)
        XCTAssertEqual(coordinator.savedModeBeforeQuietHours, .ambientAware)
    }

    func testLeavingWindowRestoresTheSavedMode() {
        let coordinator = ScheduledQuietHoursCoordinator()
        _ = coordinator.modeToRequest(nowMinutes: 1350, startMinutes: 1320, endMinutes: 420, quietHoursMode: .anc, currentMode: .talkThru)
        let result = coordinator.modeToRequest(nowMinutes: 600, startMinutes: 1320, endMinutes: 420, quietHoursMode: .anc, currentMode: .anc)
        XCTAssertEqual(result, .talkThru)
        XCTAssertNil(coordinator.savedModeBeforeQuietHours)
    }

    /// Repeated calls while still inside the window (the watcher polls every minute) must not
    /// overwrite the already-saved "before" mode with whatever the quiet-hours mode itself reports.
    func testRemainingInWindowDoesNotStompTheSavedMode() {
        let coordinator = ScheduledQuietHoursCoordinator()
        _ = coordinator.modeToRequest(nowMinutes: 1350, startMinutes: 1320, endMinutes: 420, quietHoursMode: .anc, currentMode: .talkThru)
        let secondPoll = coordinator.modeToRequest(nowMinutes: 1360, startMinutes: 1320, endMinutes: 420, quietHoursMode: .anc, currentMode: .anc)
        XCTAssertNil(secondPoll)
        XCTAssertEqual(coordinator.savedModeBeforeQuietHours, .talkThru)
    }

    /// Repeated calls while still outside the window must not try to restore a mode twice (or
    /// crash on a force-unwrap).
    func testRemainingOutsideWindowAfterRestoreIsANoOp() {
        let coordinator = ScheduledQuietHoursCoordinator()
        _ = coordinator.modeToRequest(nowMinutes: 1350, startMinutes: 1320, endMinutes: 420, quietHoursMode: .anc, currentMode: .off)
        _ = coordinator.modeToRequest(nowMinutes: 600, startMinutes: 1320, endMinutes: 420, quietHoursMode: .anc, currentMode: .anc)
        let secondPollOutside = coordinator.modeToRequest(nowMinutes: 610, startMinutes: 1320, endMinutes: 420, quietHoursMode: .anc, currentMode: .off)
        XCTAssertNil(secondPollOutside)
    }

    func testFullEnterLeaveCycleAcrossMidnightRestoresTheOriginalMode() {
        let coordinator = ScheduledQuietHoursCoordinator()
        XCTAssertEqual(
            coordinator.modeToRequest(nowMinutes: 1320, startMinutes: 1320, endMinutes: 420, quietHoursMode: .off, currentMode: .ambientAware),
            .off
        )
        XCTAssertEqual(
            coordinator.modeToRequest(nowMinutes: 420, startMinutes: 1320, endMinutes: 420, quietHoursMode: .off, currentMode: .off),
            .ambientAware
        )
    }
}
