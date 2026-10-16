import XCTest
@testable import JBLCompanion

final class WriteGuardTests: XCTestCase {
    func testEmptyAllowlistRejectsAnyWrite() {
        let guardInstance = WriteGuard(allowlist: [])
        let payload = Data([0x05, 0x5A, 0x02, 0x00, 0xD6, 0x0C])

        XCTAssertFalse(guardInstance.isAllowed(payload: payload))
    }

    func testEmptyAllowlistRejectsEvenAnEmptyPayload() {
        let guardInstance = WriteGuard(allowlist: [])
        XCTAssertFalse(guardInstance.isAllowed(payload: Data()))
    }

    func testNonEmptyAllowlistStillRejectsNonMatchingWrite() {
        let allowed = WriteAllowlistEntry(payload: Data([0x01]))
        let guardInstance = WriteGuard(allowlist: [allowed])

        XCTAssertFalse(guardInstance.isAllowed(payload: Data([0x02]))) // different payload — not an exact match
    }

    func testExactAllowlistMatchIsAllowed() {
        let entry = WriteAllowlistEntry(payload: Data([0x01]))
        let guardInstance = WriteGuard(allowlist: [entry])

        XCTAssertTrue(guardInstance.isAllowed(payload: Data([0x01])))
    }

    // MARK: - Tune770NCProfile's real allowlist (derived from isModeVerified)

    func testAllowlistAcceptsTheThreeHardwareVerifiedCommands() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)

        for mode in [CommandableNoiseMode.ambientAware, .anc, .talkThru] {
            XCTAssertTrue(guardInstance.isAllowed(payload: mode.commandFrame!), "\(mode) should be on the allowlist")
        }
    }

    func testAllowlistRejectsOffBecauseItHasNoCommandFrameAtAll() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)

        XCTAssertNil(CommandableNoiseMode.off.commandFrame, "no Off frame has ever been captured")
        // Off is unverified AND frameless, so there's nothing that could even be on the allowlist
        // for it — confirm that directly by checking the allowlist's actual entry count.
        XCTAssertEqual(profile.writeAllowlist.count, 3)
    }

    func testAllowlistRejectsTheOldUnconfirmedTalkThruHypothesisFrame() {
        // This is a *different* byte sequence from CommandableNoiseMode.talkThru.commandFrame — it's
        // the original, never-sent, never-confirmed 0B-family frame from the first iPad capture
        // (protocol.md), long before the real TalkThru frame (the one previously mislabeled "ANC")
        // was hardware-verified. That old hypothesis frame must stay rejected regardless.
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        let oldUnconfirmedHypothesisFrame = Data([0x05, 0x5A, 0x04, 0x00, 0x06, 0x0E, 0x00, 0x0B])

        XCTAssertFalse(guardInstance.isAllowed(payload: oldUnconfirmedHypothesisFrame))
    }

    func testAllowlistRejectsASingleByteChangeToAVerifiedCommand() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        var tampered = [UInt8](CommandableNoiseMode.ambientAware.commandFrame!)
        tampered[tampered.count - 1] ^= 0x01 // flip the last byte

        XCTAssertFalse(guardInstance.isAllowed(payload: Data(tampered)))
    }

    func testTune770NCProfileFlagsAmbientANCAndTalkThruAsVerifiedButNotOff() {
        let profile = Tune770NCProfile()
        XCTAssertTrue(profile.isModeVerified(.ambientAware))
        XCTAssertTrue(profile.isModeVerified(.anc))
        XCTAssertTrue(profile.isModeVerified(.talkThru))
        XCTAssertFalse(profile.isModeVerified(.off))
    }

    // MARK: - Tune670NCProfile (battery/status only — no control writes yet)

    func testTune670NCProfileHasAnEmptyAllowlist() {
        let profile = Tune670NCProfile()
        XCTAssertTrue(profile.writeAllowlist.isEmpty)
    }

    func testWriteGuardRefusesEveryKnownCommandFrameForThe670NC() {
        let profile = Tune670NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)

        for mode in CommandableNoiseMode.allCases {
            guard let frame = mode.commandFrame else { continue }
            XCTAssertFalse(guardInstance.isAllowed(payload: frame), "\(mode) must be refused — the 670NC has no verified writes")
        }
    }

    func testTune670NCProfileFlagsEveryModeAsUnverified() {
        let profile = Tune670NCProfile()
        for mode in CommandableNoiseMode.allCases {
            XCTAssertFalse(profile.isModeVerified(mode))
        }
    }

    func testDefaultProtocolExtensionTreatsEveryModeAsUnverified() {
        // GenericProfile doesn't override isModeVerified, so it should fall through to the
        // protocol extension's default (false for everything) rather than crash or assume true.
        let profile = GenericProfile()
        for mode in CommandableNoiseMode.allCases {
            XCTAssertFalse(profile.isModeVerified(mode))
        }
    }
}
