import XCTest
@testable import JBLCompanion

/// Internal, not private — also reused by RaceStreamReassemblerTests/RFCOMM-adjacent tests if any
/// need a transport fake.
@MainActor
final class FakeRaceWriteTransport: RaceWriteTransport {
    /// Independently settable, matching RFCOMMRaceLink's own two sub-conditions, so tests can
    /// drive connect/open/close/disconnect/reconnect transitions one at a time instead of only
    /// flipping a single combined "ready" bool.
    var isClassicConnected: Bool
    var isChannelOpen: Bool
    private(set) var writtenPayloads: [Data] = []

    var isReadyForRaceWrites: Bool { isClassicConnected && isChannelOpen }

    init(ready: Bool = true) {
        isClassicConnected = ready
        isChannelOpen = ready
    }

    func performRaceWrite(_ payload: Data) -> Bool {
        guard isReadyForRaceWrites else { return false }
        writtenPayloads.append(payload)
        return true
    }
}

/// An allowlist permitting every commandable mode's frame, independent of Tune770NCProfile's
/// current verified-mode allowlist — these tests are about transport readiness and rate-limiting,
/// not about which modes happen to be verified right now; that's WriteGuardTests' job.
private func permissiveWriteGuard() -> WriteGuard {
    WriteGuard(allowlist: CommandableNoiseMode.allCases.compactMap { $0.commandFrame.map { WriteAllowlistEntry(payload: $0) } })
}

@MainActor
final class NoiseControlCommanderTests: XCTestCase {
    private func makeCommander(transport: FakeRaceWriteTransport, now: @escaping () -> Date = Date.init) -> NoiseControlCommander {
        NoiseControlCommander(writeGuard: permissiveWriteGuard(), transport: transport, now: now)
    }

    func testSendsWhenReady() {
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = makeCommander(transport: transport)
        XCTAssertTrue(commander.setMode(.anc))
        XCTAssertEqual(transport.writtenPayloads, [CommandableNoiseMode.anc.commandFrame!])
    }

    func testRefusesToSendWhenLinkNotReady() {
        let transport = FakeRaceWriteTransport(ready: false)
        let commander = makeCommander(transport: transport)
        XCTAssertFalse(commander.setMode(.anc))
        XCTAssertTrue(transport.writtenPayloads.isEmpty)
    }

    func testRefusesToSendWhenNotAllowlisted() {
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = NoiseControlCommander(writeGuard: WriteGuard(allowlist: []), transport: transport)
        XCTAssertFalse(commander.setMode(.anc))
    }

    /// Off has its own captured command frame now (CommandableNoiseMode.commandFrame's own doc
    /// comment) — setMode sends it exactly like any other mode.
    func testSendsOffLikeAnyOtherMode() {
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = makeCommander(transport: transport)
        XCTAssertTrue(commander.setMode(.off))
        XCTAssertEqual(transport.writtenPayloads, [CommandableNoiseMode.off.commandFrame!])
    }

    func testEnforcesMinimumIntervalBetweenWrites() {
        let transport = FakeRaceWriteTransport(ready: true)
        var now = Date(timeIntervalSince1970: 0)
        let commander = makeCommander(transport: transport, now: { now })

        XCTAssertTrue(commander.setMode(.ambientAware))
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

// MARK: - send(_:label:) — the generic guarded-write path setMode and power-off both share

@MainActor
final class NoiseControlCommanderSendTests: XCTestCase {
    private let powerOffFrame = Data([0x05, 0x5A, 0x04, 0x00, 0x01, 0x11, 0x18, 0x00])

    private func makeCommander(transport: FakeRaceWriteTransport, allowlist: [Data]) -> NoiseControlCommander {
        NoiseControlCommander(writeGuard: WriteGuard(allowlist: allowlist.map { WriteAllowlistEntry(payload: $0) }), transport: transport)
    }

    func testSendGoesThroughWhenReadyAndAllowlisted() {
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = makeCommander(transport: transport, allowlist: [powerOffFrame])
        XCTAssertTrue(commander.send(powerOffFrame, label: "power-off"))
        XCTAssertEqual(transport.writtenPayloads, [powerOffFrame])
    }

    func testSendRefusesWhenLinkNotReady() {
        let transport = FakeRaceWriteTransport(ready: false)
        let commander = makeCommander(transport: transport, allowlist: [powerOffFrame])
        XCTAssertFalse(commander.send(powerOffFrame, label: "power-off"))
        XCTAssertTrue(transport.writtenPayloads.isEmpty)
    }

    func testSendRefusesWhenNotAllowlisted() {
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = makeCommander(transport: transport, allowlist: [])
        XCTAssertFalse(commander.send(powerOffFrame, label: "power-off"))
        XCTAssertTrue(transport.writtenPayloads.isEmpty)
    }

    func testSendSharesTheSameRateLimitAsSetMode() {
        let transport = FakeRaceWriteTransport(ready: true)
        var now = Date(timeIntervalSince1970: 0)
        let commander = NoiseControlCommander(
            writeGuard: WriteGuard(allowlist: [powerOffFrame, CommandableNoiseMode.anc.commandFrame!].map { WriteAllowlistEntry(payload: $0) }),
            transport: transport, now: { now }
        )
        XCTAssertTrue(commander.setMode(.anc))
        now = now.addingTimeInterval(0.1) // well under the 500ms minimum
        XCTAssertFalse(commander.send(powerOffFrame, label: "power-off"))
        XCTAssertEqual(transport.writtenPayloads.count, 1)
    }
}

// MARK: - Readiness state transitions (connect, channel open, close, disconnect, reconnect)

@MainActor
final class NoiseControlCommanderReadinessTransitionTests: XCTestCase {
    private func makeCommander(transport: FakeRaceWriteTransport, now: @escaping () -> Date = Date.init) -> NoiseControlCommander {
        NoiseControlCommander(writeGuard: permissiveWriteGuard(), transport: transport, now: now)
    }

    /// Both sub-conditions (classic connected, RFCOMM channel open) must be true before a command
    /// can go out — refused if either one isn't, not just when neither are.
    func testRefusesUntilBothSubConditionsAreTrue() {
        let transport = FakeRaceWriteTransport(ready: false)
        let commander = makeCommander(transport: transport)

        // Disconnected: nothing is true yet.
        XCTAssertFalse(commander.setMode(.anc))

        // Classic connected, but the RFCOMM channel hasn't opened yet.
        transport.isClassicConnected = true
        XCTAssertFalse(commander.setMode(.anc))

        // Channel open — now both are true, and the command goes through.
        transport.isChannelOpen = true
        XCTAssertTrue(commander.setMode(.anc))
        XCTAssertEqual(transport.writtenPayloads, [CommandableNoiseMode.anc.commandFrame!])
    }

    /// A disconnect must revoke readiness, and readiness must come back once reconnect/reopen
    /// finishes — a stale "still ready" or a permanently-stuck "never ready again" would both be
    /// bugs the commander should never paper over.
    func testDisconnectRevokesReadinessUntilReconnectRestoresIt() {
        let transport = FakeRaceWriteTransport(ready: true)
        var now = Date(timeIntervalSince1970: 0)
        let commander = makeCommander(transport: transport, now: { now })

        XCTAssertTrue(commander.setMode(.ambientAware))

        // Disconnect: a fresh reopen on reconnect would clear both sub-conditions.
        transport.isClassicConnected = false
        transport.isChannelOpen = false
        now = now.addingTimeInterval(1) // past the 500ms rate limit, so this isn't what refuses it
        XCTAssertFalse(commander.setMode(.anc))

        // Reconnect: classic link back up and the channel reopened.
        transport.isClassicConnected = true
        transport.isChannelOpen = true
        now = now.addingTimeInterval(1)
        XCTAssertTrue(commander.setMode(.anc))
        XCTAssertEqual(transport.writtenPayloads, [CommandableNoiseMode.ambientAware.commandFrame!, CommandableNoiseMode.anc.commandFrame!])
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

    /// A spontaneous mode change (earcup button press) reports straight through
    /// `handleConfirmation` with no prior `requestMode` call at all — design/DESIGN_GUIDE.md §9.3
    /// point 5: "apply it the same way as a confirmation, with no pending step."
    func testHardwareInitiatedChangeAppliesWithNoPendingStep() {
        let state = HeadphoneState()
        state.noiseMode = .off
        let sender = FakeNoiseModeSending()
        let (coordinator, _) = makeCoordinator(sender: sender, state: state)

        coordinator.handleConfirmation(.talkThru)

        XCTAssertEqual(state.noiseMode, .talkThru)
        XCTAssertNil(state.pendingNoiseMode)
        XCTAssertFalse(state.noiseModeConfirmationTimedOut)
        // Never sent a command on the device's behalf — this was the headphones telling us.
        XCTAssertTrue(sender.requestedModes.isEmpty)
    }

    /// Off has its own captured command frame now (CommandableNoiseMode.commandFrame's own doc
    /// comment) — requesting it goes through the exact same send/pending/confirmation path as any
    /// other mode, no special-casing.
    func testRequestingOffGoesThroughTheNormalPendingConfirmationPath() {
        let state = HeadphoneState()
        state.noiseMode = .anc
        let sender = FakeNoiseModeSending()
        let (coordinator, _) = makeCoordinator(sender: sender, state: state)

        coordinator.requestMode(.off)

        XCTAssertEqual(state.noiseMode, .anc, "must stay the prior confirmed mode until a real confirmation arrives")
        XCTAssertEqual(state.pendingNoiseMode, .off)
        XCTAssertEqual(sender.requestedModes, [.off])

        coordinator.handleConfirmation(.off)
        XCTAssertEqual(state.noiseMode, .off)
        XCTAssertNil(state.pendingNoiseMode)
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
