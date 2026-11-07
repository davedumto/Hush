import XCTest
@testable import JBLCompanion

final class LowBatteryAlertCoordinatorTests: XCTestCase {
    func testStartRequestsAuthorization() {
        let notifier = FakeLowBatteryNotifier()
        let coordinator = LowBatteryAlertCoordinator(notifier: notifier)
        coordinator.start()
        XCTAssertEqual(notifier.requestAuthorizationCallCount, 1)
    }

    func testDoesNotAlertAtOrAboveThreshold() {
        let notifier = FakeLowBatteryNotifier()
        let coordinator = LowBatteryAlertCoordinator(notifier: notifier)
        coordinator.update(batteryPercent: PillVariant.lowBatteryThreshold, deviceName: "Tune 770NC")
        coordinator.update(batteryPercent: 100, deviceName: "Tune 770NC")
        XCTAssertTrue(notifier.postedAlerts.isEmpty)
    }

    func testAlertsOnceWhenCrossingBelowThreshold() {
        let notifier = FakeLowBatteryNotifier()
        let coordinator = LowBatteryAlertCoordinator(notifier: notifier)
        coordinator.update(batteryPercent: PillVariant.lowBatteryThreshold - 1, deviceName: "Tune 770NC")
        XCTAssertEqual(notifier.postedAlerts.count, 1)
        XCTAssertEqual(notifier.postedAlerts.first?.deviceName, "Tune 770NC")
        XCTAssertEqual(notifier.postedAlerts.first?.batteryPercent, PillVariant.lowBatteryThreshold - 1)
    }

    func testDoesNotReAlertOnRepeatedLowReadingsWithoutRecovery() {
        let notifier = FakeLowBatteryNotifier()
        let coordinator = LowBatteryAlertCoordinator(notifier: notifier)
        coordinator.update(batteryPercent: 10, deviceName: "Tune 770NC")
        coordinator.update(batteryPercent: 9, deviceName: "Tune 770NC")
        coordinator.update(batteryPercent: 8, deviceName: "Tune 770NC")
        XCTAssertEqual(notifier.postedAlerts.count, 1)
    }

    func testAlertsAgainAfterRecoveringAboveThresholdThenDroppingLowAgain() {
        let notifier = FakeLowBatteryNotifier()
        let coordinator = LowBatteryAlertCoordinator(notifier: notifier)
        coordinator.update(batteryPercent: 10, deviceName: "Tune 770NC")
        coordinator.update(batteryPercent: 100, deviceName: "Tune 770NC") // recharged
        coordinator.update(batteryPercent: 10, deviceName: "Tune 770NC") // low again
        XCTAssertEqual(notifier.postedAlerts.count, 2)
    }

    func testAlertsAgainAfterDisconnectingThenReconnectingLow() {
        let notifier = FakeLowBatteryNotifier()
        let coordinator = LowBatteryAlertCoordinator(notifier: notifier)
        coordinator.update(batteryPercent: 10, deviceName: "Tune 770NC")
        coordinator.update(batteryPercent: nil, deviceName: "") // disconnected
        coordinator.update(batteryPercent: 10, deviceName: "Tune 770NC") // reconnected, still low
        XCTAssertEqual(notifier.postedAlerts.count, 2)
    }

    func testNilBatteryPercentNeverAlertsOnItsOwn() {
        let notifier = FakeLowBatteryNotifier()
        let coordinator = LowBatteryAlertCoordinator(notifier: notifier)
        coordinator.update(batteryPercent: nil, deviceName: "")
        XCTAssertTrue(notifier.postedAlerts.isEmpty)
    }

    func testFallsBackToGenericNameWhenDeviceNameIsEmpty() {
        let notifier = FakeLowBatteryNotifier()
        let coordinator = LowBatteryAlertCoordinator(notifier: notifier)
        coordinator.update(batteryPercent: 10, deviceName: "")
        XCTAssertEqual(notifier.postedAlerts.first?.deviceName, "Your headphones")
    }
}

final class FakeLowBatteryNotifier: LowBatteryNotifying {
    private(set) var requestAuthorizationCallCount = 0
    private(set) var postedAlerts: [(deviceName: String, batteryPercent: Int)] = []

    func requestAuthorizationIfNeeded() {
        requestAuthorizationCallCount += 1
    }

    func postLowBatteryAlert(deviceName: String, batteryPercent: Int) {
        postedAlerts.append((deviceName, batteryPercent))
    }
}
