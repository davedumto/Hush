import CoreBluetooth
import XCTest
@testable import JBLCompanion

@MainActor
private final class FakeRaceWriteTransport: RaceWriteTransport {
    var isReadyForRaceWrites: Bool
    var raceWriteCharacteristicUUID: CBUUID?
    private(set) var writtenPayloads: [Data] = []

    init(ready: Bool = true, characteristicUUID: CBUUID? = CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45")) {
        isReadyForRaceWrites = ready
        raceWriteCharacteristicUUID = characteristicUUID
    }

    func performRaceWrite(_ payload: Data) -> Bool {
        guard isReadyForRaceWrites else { return false }
        writtenPayloads.append(payload)
        return true
    }
}

@MainActor
final class NoiseControlCommanderTests: XCTestCase {
    private func makeCommander(transport: FakeRaceWriteTransport, now: @escaping () -> Date = Date.init) -> NoiseControlCommander {
        let profile = Tune770NCProfile()
        let writeGuard = WriteGuard(allowlist: profile.writeAllowlist)
        return NoiseControlCommander(profile: profile, writeGuard: writeGuard, transport: transport, now: now)
    }

    func testSendsWhenReady() {
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = makeCommander(transport: transport)
        XCTAssertTrue(commander.setMode(.anc))
        XCTAssertEqual(transport.writtenPayloads, [CommandableNoiseMode.anc.commandFrame])
    }

    func testRefusesToSendWhenLinkNotReady() {
        let transport = FakeRaceWriteTransport(ready: false)
        let commander = makeCommander(transport: transport)
        XCTAssertFalse(commander.setMode(.off))
        XCTAssertTrue(transport.writtenPayloads.isEmpty)
    }

    func testRefusesToSendWhenNoWriteCharacteristicDiscoveredYet() {
        let transport = FakeRaceWriteTransport(ready: true, characteristicUUID: nil)
        let commander = makeCommander(transport: transport)
        XCTAssertFalse(commander.setMode(.off))
    }

    func testEnforcesMinimumIntervalBetweenWrites() {
        let transport = FakeRaceWriteTransport(ready: true)
        var now = Date(timeIntervalSince1970: 0)
        let commander = makeCommander(transport: transport, now: { now })

        XCTAssertTrue(commander.setMode(.off))
        now = now.addingTimeInterval(0.1) // well under the 500ms minimum
        XCTAssertFalse(commander.setMode(.anc))
        XCTAssertEqual(transport.writtenPayloads.count, 1)

        now = now.addingTimeInterval(0.5) // now 0.6s after the first write — past the limit
        XCTAssertTrue(commander.setMode(.anc))
        XCTAssertEqual(transport.writtenPayloads.count, 2)
    }

    func testNeverRetriesOnItsOwn() {
        // setMode is the only entry point; calling it once never produces more than one write.
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = makeCommander(transport: transport)
        _ = commander.setMode(.anc)
        XCTAssertEqual(transport.writtenPayloads.count, 1)
    }
}

// MARK: - NoiseModeRequestCoordinator (pending state, no-optimistic-update, timeout)

@MainActor
private final class FakeNoiseModeSending: NoiseModeSending {
    var result = true
    private(set) var requestedModes: [CommandableNoiseMode] = []

    func setMode(_ mode: CommandableNoiseMode) -> Bool {
        requestedModes.append(mode)
        return result
    }
}

@MainActor
final class NoiseModeRequestCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        sender: FakeNoiseModeSending, state: HeadphoneState
    ) -> (NoiseModeRequestCoordinator, pendingTimeouts: () -> [() -> Void]) {
        var scheduled: [() -> Void] = []
        let coordinator = NoiseModeRequestCoordinator(
            state: state, sender: sender,
            scheduleTimeout: { callback in scheduled.append(callback) }
        )
        return (coordinator, { scheduled })
    }

    func testRequestDoesNotChangeConfirmedModeOptimistically() {
        let state = HeadphoneState()
        state.noiseMode = .off
        let sender = FakeNoiseModeSending()
        let (coordinator, _) = makeCoordinator(sender: sender, state: state)

        coordinator.requestMode(.anc)

        // The click must only set `pendingNoiseMode` — `noiseMode` itself stays exactly as it
        // was until a real confirmation event arrives.
        XCTAssertEqual(state.noiseMode, .off)
        XCTAssertEqual(state.pendingNoiseMode, .anc)
    }

    func testConfirmationUpdatesNoiseModeAndClearsPending() {
        let state = HeadphoneState()
        let sender = FakeNoiseModeSending()
        let (coordinator, _) = makeCoordinator(sender: sender, state: state)

        coordinator.requestMode(.anc)
        coordinator.handleConfirmation(.anc)

        XCTAssertEqual(state.noiseMode, .anc)
        XCTAssertNil(state.pendingNoiseMode)
        XCTAssertFalse(state.noiseModeConfirmationTimedOut)
    }

    func testIgnoresASecondRequestWhileOnePending() {
        let state = HeadphoneState()
        let sender = FakeNoiseModeSending()
        let (coordinator, _) = makeCoordinator(sender: sender, state: state)

        coordinator.requestMode(.anc)
        coordinator.requestMode(.off) // should be ignored — one is already pending

        XCTAssertEqual(sender.requestedModes, [.anc])
        XCTAssertEqual(state.pendingNoiseMode, .anc)
    }

    func testTimeoutShowsNoConfirmationAndNeverRetries() {
        let state = HeadphoneState()
        let sender = FakeNoiseModeSending()
        let (coordinator, pendingTimeouts) = makeCoordinator(sender: sender, state: state)

        coordinator.requestMode(.anc)
        XCTAssertEqual(pendingTimeouts().count, 1)

        pendingTimeouts().first?() // simulate the 2s window elapsing with no confirmation

        XCTAssertNil(state.pendingNoiseMode)
        XCTAssertTrue(state.noiseModeConfirmationTimedOut)
        // Only the original request was ever sent — the timeout itself never calls setMode again.
        XCTAssertEqual(sender.requestedModes, [.anc])
    }

    func testTimeoutIsANoOpIfConfirmationAlreadyArrived() {
        let state = HeadphoneState()
        let sender = FakeNoiseModeSending()
        let (coordinator, pendingTimeouts) = makeCoordinator(sender: sender, state: state)

        coordinator.requestMode(.anc)
        coordinator.handleConfirmation(.anc)
        pendingTimeouts().first?() // fires late, after confirmation already resolved things

        XCTAssertEqual(state.noiseMode, .anc)
        XCTAssertFalse(state.noiseModeConfirmationTimedOut)
    }
}
