import XCTest
@testable import JBLCompanion

/// An allowlist permitting every frame in every EqualizerPreset's transaction — these tests are
/// about transport readiness/allowlist-refusal/send-ordering, not about which model happens to
/// have isEqualizerVerified set; that's WriteGuardTests' job.
private func permissiveEqualizerWriteGuard() -> WriteGuard {
    WriteGuard(allowlist: EqualizerPreset.allCases.flatMap(\.transaction).map { WriteAllowlistEntry(payload: $0) })
}

@MainActor
final class EqualizerCommanderTests: XCTestCase {
    func testSendsEveryFrameInOrderWhenReady() async {
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = EqualizerCommander(writeGuard: permissiveEqualizerWriteGuard(), transport: transport, interFrameGap: 0)
        let sent = await commander.setPreset(.bass)
        XCTAssertTrue(sent)
        XCTAssertEqual(transport.writtenPayloads, EqualizerPreset.bass.transaction)
    }

    func testRefusesWhenLinkNotReady() async {
        let transport = FakeRaceWriteTransport(ready: false)
        let commander = EqualizerCommander(writeGuard: permissiveEqualizerWriteGuard(), transport: transport, interFrameGap: 0)
        let sent = await commander.setPreset(.jazz)
        XCTAssertFalse(sent)
        XCTAssertTrue(transport.writtenPayloads.isEmpty)
    }

    func testRefusesEntirelyWhenAnySingleFrameIsNotAllowlisted() async {
        // Only Bass's frames are allowlisted — selecting Jazz must refuse outright, not send
        // whichever of Jazz's frames happen to coincidentally match something in the list.
        let writeGuard = WriteGuard(allowlist: EqualizerPreset.bass.transaction.map { WriteAllowlistEntry(payload: $0) })
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = EqualizerCommander(writeGuard: writeGuard, transport: transport, interFrameGap: 0)
        let sent = await commander.setPreset(.jazz)
        XCTAssertFalse(sent)
        XCTAssertTrue(transport.writtenPayloads.isEmpty)
    }

    func testRefusesASecondTransactionWhileOneIsAlreadyInFlight() async {
        let transport = FakeRaceWriteTransport(ready: true)
        let commander = EqualizerCommander(writeGuard: permissiveEqualizerWriteGuard(), transport: transport, interFrameGap: 0.05)
        async let first = commander.setPreset(.studio)
        // Give the first call a moment to set isSending before the second one checks it.
        try? await Task.sleep(nanoseconds: 5_000_000)
        let second = await commander.setPreset(.club)
        XCTAssertFalse(second)
        let firstResult = await first
        XCTAssertTrue(firstResult)
    }
}
