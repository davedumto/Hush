import CoreBluetooth
import XCTest
@testable import JBLCompanion

@MainActor
private final class FakeRaceNotifySubscribing: RaceNotifySubscribing {
    private(set) var subscribeCallCount = 0

    func subscribeToRaceNotify() {
        subscribeCallCount += 1
    }
}

@MainActor
final class RaceSubscriptionCoordinatorTests: XCTestCase {
    private let insufficientEncryption = CBATTError(.insufficientEncryption)
    private let insufficientAuthentication = CBATTError(.insufficientAuthentication)

    /// `fireNextRetry` runs the oldest still-pending scheduled retry (FIFO, matching how a real
    /// timer queue would fire them) and reports whether there was one to run.
    private func makeCoordinator(
        subscriber: FakeRaceNotifySubscribing
    ) -> (coordinator: RaceSubscriptionCoordinator, fireNextRetry: () -> Bool) {
        var scheduled: [() -> Void] = []
        let coordinator = RaceSubscriptionCoordinator(
            subscriber: subscriber,
            scheduleRetry: { callback in scheduled.append(callback) }
        )
        let fireNextRetry: () -> Bool = {
            guard !scheduled.isEmpty else { return false }
            scheduled.removeFirst()()
            return true
        }
        return (coordinator, fireNextRetry)
    }

    func testInsufficientEncryptionTriggersNeedsPairingAndSchedulesARetry() {
        let subscriber = FakeRaceNotifySubscribing()
        let (coordinator, fireNextRetry) = makeCoordinator(subscriber: subscriber)

        coordinator.handleConnect()
        XCTAssertEqual(coordinator.status, .connecting)

        coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientEncryption)
        XCTAssertEqual(coordinator.status, .needsPairing)
        XCTAssertEqual(coordinator.lastErrorCode, 15)

        XCTAssertTrue(fireNextRetry())
        XCTAssertEqual(subscriber.subscribeCallCount, 1)
        XCTAssertEqual(coordinator.retryCount, 1)
    }

    func testInsufficientAuthenticationAlsoTriggersNeedsPairing() {
        let subscriber = FakeRaceNotifySubscribing()
        let (coordinator, _) = makeCoordinator(subscriber: subscriber)

        coordinator.handleConnect()
        coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientAuthentication)

        XCTAssertEqual(coordinator.status, .needsPairing)
        XCTAssertEqual(coordinator.lastErrorCode, 5)
    }

    func testUnrelatedErrorDoesNotTriggerPairingOrARetry() {
        let subscriber = FakeRaceNotifySubscribing()
        let (coordinator, fireNextRetry) = makeCoordinator(subscriber: subscriber)

        coordinator.handleConnect()
        coordinator.handleSubscriptionResult(isNotifying: false, error: CBATTError(.unlikelyError))

        XCTAssertEqual(coordinator.status, .connecting)
        XCTAssertNil(coordinator.lastErrorDomain)
        XCTAssertFalse(fireNextRetry())
    }

    func testErrorThenErrorThenSuccessOnRetryBecomesReady() {
        let subscriber = FakeRaceNotifySubscribing()
        let (coordinator, fireNextRetry) = makeCoordinator(subscriber: subscriber)

        coordinator.handleConnect()
        coordinator.handleWriteCharacteristicDiscovered()

        coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientEncryption)
        XCTAssertTrue(fireNextRetry()) // retry attempt 1
        coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientAuthentication)
        XCTAssertTrue(fireNextRetry()) // retry attempt 2

        // The user accepted the macOS pairing prompt between the second and third attempts.
        coordinator.handleSubscriptionResult(isNotifying: true, error: nil)

        XCTAssertEqual(coordinator.status, .ready)
        XCTAssertNil(coordinator.lastErrorDomain)
        XCTAssertTrue(coordinator.isSubscribed)
    }

    func testNeverRetriesMoreThanFourTimes() {
        let subscriber = FakeRaceNotifySubscribing()
        let (coordinator, fireNextRetry) = makeCoordinator(subscriber: subscriber)

        coordinator.handleConnect()
        coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientEncryption)

        for _ in 0..<RaceSubscriptionCoordinator.maxRetries {
            XCTAssertTrue(fireNextRetry())
            coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientEncryption)
        }

        // The 4th retry's failure must not schedule a 5th.
        XCTAssertFalse(fireNextRetry())
        XCTAssertEqual(coordinator.retryCount, RaceSubscriptionCoordinator.maxRetries)
        XCTAssertEqual(subscriber.subscribeCallCount, RaceSubscriptionCoordinator.maxRetries)
        XCTAssertEqual(coordinator.status, .needsPairing)
    }

    func testDisconnectCancelsAPendingRetry() {
        let subscriber = FakeRaceNotifySubscribing()
        let (coordinator, fireNextRetry) = makeCoordinator(subscriber: subscriber)

        coordinator.handleConnect()
        coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientEncryption)

        coordinator.handleDisconnect()
        XCTAssertEqual(coordinator.status, .notConnected)

        // The retry timer firing late (after disconnect) must not call back into the subscriber.
        XCTAssertTrue(fireNextRetry())
        XCTAssertEqual(subscriber.subscribeCallCount, 0)
    }

    func testReconnectAfterDisconnectStartsRetryCountFresh() {
        let subscriber = FakeRaceNotifySubscribing()
        let (coordinator, fireNextRetry) = makeCoordinator(subscriber: subscriber)

        coordinator.handleConnect()
        coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientEncryption)
        _ = fireNextRetry()
        XCTAssertEqual(coordinator.retryCount, 1)

        coordinator.handleDisconnect()
        coordinator.handleConnect()

        XCTAssertEqual(coordinator.retryCount, 0)
        XCTAssertEqual(coordinator.status, .connecting)
    }

    /// Mirrors the coordinator's `isSubscribed` into a RaceWriteTransport fake, the way
    /// BLEBatteryLink's own RaceWriteTransport conformance does, and confirms
    /// NoiseControlCommander never sends a write for as long as that stays false.
    func testNoWriteIsAttemptedWhileNeedsPairing() {
        let subscriber = FakeRaceNotifySubscribing()
        let (coordinator, fireNextRetry) = makeCoordinator(subscriber: subscriber)
        let profile = Tune770NCProfile()
        let writeGuard = WriteGuard(allowlist: profile.writeAllowlist)
        let transport = FakeRaceWriteTransport(ready: false)
        let commander = NoiseControlCommander(profile: profile, writeGuard: writeGuard, transport: transport)

        func syncTransport() {
            transport.isPeripheralConnected = true
            transport.isRaceNotifySubscribed = coordinator.isSubscribed
        }

        coordinator.handleConnect()
        coordinator.handleWriteCharacteristicDiscovered()
        syncTransport()
        XCTAssertFalse(commander.setMode(.anc))

        coordinator.handleSubscriptionResult(isNotifying: false, error: insufficientEncryption)
        syncTransport()
        XCTAssertEqual(coordinator.status, .needsPairing)
        XCTAssertFalse(commander.setMode(.anc))

        XCTAssertTrue(fireNextRetry())
        syncTransport()
        XCTAssertFalse(commander.setMode(.anc))

        XCTAssertTrue(transport.writtenPayloads.isEmpty)
    }
}
