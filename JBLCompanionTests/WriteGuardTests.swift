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

    func testAllowlistAcceptsOnlyTheVerifiedAmbientCommand() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)

        XCTAssertTrue(guardInstance.isAllowed(payload: CommandableNoiseMode.ambientAware.commandFrame))
    }

    func testAllowlistRejectsTheUnverifiedOffAndANCCommands() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)

        XCTAssertFalse(guardInstance.isAllowed(payload: CommandableNoiseMode.off.commandFrame))
        XCTAssertFalse(guardInstance.isAllowed(payload: CommandableNoiseMode.anc.commandFrame))
    }

    func testAllowlistRejectsTheUnconfirmedTalkThruFrame() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        let talkThruFrame = Data([0x05, 0x5A, 0x04, 0x00, 0x06, 0x0E, 0x00, 0x0B])

        XCTAssertFalse(guardInstance.isAllowed(payload: talkThruFrame))
    }

    func testAllowlistRejectsASingleByteChangeToTheVerifiedCommand() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        var tampered = [UInt8](CommandableNoiseMode.ambientAware.commandFrame)
        tampered[tampered.count - 1] ^= 0x01 // flip the last byte

        XCTAssertFalse(guardInstance.isAllowed(payload: Data(tampered)))
    }

    func testTune770NCProfileFlagsOnlyAmbientAsVerified() {
        let profile = Tune770NCProfile()
        XCTAssertFalse(profile.isModeVerified(.off))
        XCTAssertFalse(profile.isModeVerified(.anc))
        XCTAssertTrue(profile.isModeVerified(.ambientAware))
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
