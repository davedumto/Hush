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

    func testAllowlistAcceptsAllFourHardwareVerifiedCommands() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)

        for mode in CommandableNoiseMode.allCases {
            XCTAssertTrue(guardInstance.isAllowed(payload: mode.commandFrame!), "\(mode) should be on the allowlist")
        }
    }

    func testAllowlistEntryCount() {
        let profile = Tune770NCProfile()
        // Owner directive, 2026-10-22: 670NC verification now carries over to the 770NC — 4 noise
        // modes (Ambient, ANC, TalkThru, Off — CommandableNoiseMode.commandFrame's own doc comment
        // on how Off's frame was finally found and hardware-confirmed) + 1 power-off frame + 72
        // equalizer frames + 4 device-toggle frames = 81, same as 670NC.
        XCTAssertEqual(profile.writeAllowlist.count, 81)
    }

    func testAllowlistRejectsTheOldUnconfirmedTalkThruHypothesisFrame() {
        // This is a *different* byte sequence from CommandableNoiseMode.talkThru.commandFrame — it's
        // a 0A-family frame hypothesis from the first iPad capture (protocol.md), long before the
        // real TalkThru frame (the one previously mislabeled "ANC") was hardware-verified. That old
        // hypothesis frame must stay rejected regardless. (NOT the same bytes as
        // CommandableNoiseMode.off.commandFrame, `05 5A 04 00 06 0E 00 0B` — that one really is
        // verified now, CommandableNoiseMode.commandFrame's own doc comment, so a test here can no
        // longer use it as a "should be rejected" example.)
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        let oldUnconfirmedHypothesisFrame = Data([0x05, 0x5A, 0x04, 0x00, 0x06, 0x0E, 0x00, 0x09])

        XCTAssertFalse(guardInstance.isAllowed(payload: oldUnconfirmedHypothesisFrame))
    }

    func testAllowlistRejectsASingleByteChangeToAVerifiedCommand() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        var tampered = [UInt8](CommandableNoiseMode.ambientAware.commandFrame!)
        tampered[tampered.count - 1] ^= 0x01 // flip the last byte

        XCTAssertFalse(guardInstance.isAllowed(payload: Data(tampered)))
    }

    func testTune770NCProfileFlagsAllFourModesAsVerified() {
        let profile = Tune770NCProfile()
        XCTAssertTrue(profile.isModeVerified(.ambientAware))
        XCTAssertTrue(profile.isModeVerified(.anc))
        XCTAssertTrue(profile.isModeVerified(.talkThru))
        // Off's own frame was finally found and hardware-confirmed 2026-10-22 — see
        // CommandableNoiseMode.commandFrame's own doc comment for the two disproven hypotheses
        // that came before it.
        XCTAssertTrue(profile.isModeVerified(.off))
    }

    // MARK: - Tune670NCProfile's real allowlist (hardware-verified directly on the 670NC,
    // ~/jbl-recon/rfcomm_send_test_670nc.swift — identical command frames to the 770NC)

    func testTune670NCAllowlistAcceptsAllFourHardwareVerifiedCommands() {
        let profile = Tune670NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)

        for mode in CommandableNoiseMode.allCases {
            XCTAssertTrue(guardInstance.isAllowed(payload: mode.commandFrame!), "\(mode) should be on the allowlist")
        }
    }

    func testTune670NCAllowlistEntryCount() {
        let profile = Tune670NCProfile()
        // 4 noise modes (Ambient, ANC, TalkThru, Off) + 1 power-off frame + 72 equalizer frames (6
        // presets x 12 frames each, EqualizerPreset's own doc comment) + 4 device-toggle frames
        // (Max Volume Limiter + Voice Prompt, DeviceToggle's own doc comment — 2 states each) = 81.
        XCTAssertEqual(profile.writeAllowlist.count, 81)
    }

    func testTune670NCProfileFlagsAllFourModesAsVerified() {
        let profile = Tune670NCProfile()
        XCTAssertTrue(profile.isModeVerified(.ambientAware))
        XCTAssertTrue(profile.isModeVerified(.anc))
        XCTAssertTrue(profile.isModeVerified(.talkThru))
        XCTAssertTrue(profile.isModeVerified(.off))
    }

    // MARK: - GenericProfile (no control writes at all — the true "nothing verified" baseline)

    func testGenericProfileHasAnEmptyAllowlist() {
        XCTAssertTrue(GenericProfile().writeAllowlist.isEmpty)
    }

    func testDefaultProtocolExtensionTreatsEveryModeAsUnverified() {
        // GenericProfile doesn't override isModeVerified, so it should fall through to the
        // protocol extension's default (false for everything) rather than crash or assume true.
        let profile = GenericProfile()
        for mode in CommandableNoiseMode.allCases {
            XCTAssertFalse(profile.isModeVerified(mode))
        }
    }

    func testGenericProfileHasNoPowerOffFrameOrVerification() {
        // Protocol extension defaults (nil/false) — GenericProfile doesn't override either.
        let profile = GenericProfile()
        XCTAssertNil(profile.powerOffCommandFrame)
        XCTAssertFalse(profile.isPowerOffVerified)
    }

    // MARK: - Power-off (DeviceProfile.powerOffCommandFrame's own doc comment)

    func testTune670NCPowerOffIsVerifiedAndIncludedInTheAllowlist() {
        let profile = Tune670NCProfile()
        let frame = Data([0x05, 0x5A, 0x04, 0x00, 0x01, 0x11, 0x18, 0x00])
        XCTAssertEqual(profile.powerOffCommandFrame, frame)
        XCTAssertTrue(profile.isPowerOffVerified)
        XCTAssertTrue(profile.writeAllowlist.contains(WriteAllowlistEntry(payload: frame)))
    }

    func testTune770NCPowerOffIsVerifiedAndIncludedInTheAllowlist() {
        // Owner directive, 2026-10-22: 670NC verification now carries over to the 770NC (same
        // bytes, same shared RACE protocol — Tune770NCProfile's own doc comment).
        let profile = Tune770NCProfile()
        let frame = Data([0x05, 0x5A, 0x04, 0x00, 0x01, 0x11, 0x18, 0x00])
        XCTAssertEqual(profile.powerOffCommandFrame, frame)
        XCTAssertTrue(profile.isPowerOffVerified)
        XCTAssertTrue(profile.writeAllowlist.contains(WriteAllowlistEntry(payload: frame)))
    }

    // MARK: - Device toggles (DeviceToggle's own doc comment)

    func testTune670NCMaxVolumeLimiterIsVerifiedAndBothStatesAreInTheAllowlist() {
        let profile = Tune670NCProfile()
        XCTAssertTrue(profile.isMaxVolumeLimiterVerified)
        for frame in DeviceToggle.maxVolumeLimiter.bothStateFrames {
            XCTAssertTrue(profile.writeAllowlist.contains(WriteAllowlistEntry(payload: frame)))
        }
    }

    func testTune670NCVoicePromptIsVerifiedAndBothStatesAreInTheAllowlist() {
        let profile = Tune670NCProfile()
        XCTAssertTrue(profile.isVoicePromptVerified)
        for frame in DeviceToggle.voicePrompt.bothStateFrames {
            XCTAssertTrue(profile.writeAllowlist.contains(WriteAllowlistEntry(payload: frame)))
        }
    }

    func testTune770NCDeviceTogglesAreVerifiedAndInTheAllowlist() {
        // Owner directive, 2026-10-22: 670NC verification now carries over to the 770NC.
        let profile = Tune770NCProfile()
        XCTAssertTrue(profile.isMaxVolumeLimiterVerified)
        XCTAssertTrue(profile.isVoicePromptVerified)
        for frame in DeviceToggle.maxVolumeLimiter.bothStateFrames + DeviceToggle.voicePrompt.bothStateFrames {
            XCTAssertTrue(profile.writeAllowlist.contains(WriteAllowlistEntry(payload: frame)))
        }
    }

    func testGenericProfileHasDeviceTogglesUnverified() {
        let profile = GenericProfile()
        XCTAssertFalse(profile.isMaxVolumeLimiterVerified)
        XCTAssertFalse(profile.isVoicePromptVerified)
    }

    // MARK: - Off (CommandableNoiseMode.commandFrame's own doc comment — the third, finally
    // correct hypothesis, hardware-confirmed 2026-10-22 on the 770NC via
    // ~/jbl-recon/rfcomm_send_off_770nc.swift)

    func testOffCommandFrameMatchesTheHardwareConfirmedBytes() {
        XCTAssertEqual(CommandableNoiseMode.off.commandFrame, Data([0x05, 0x5A, 0x04, 0x00, 0x06, 0x0E, 0x00, 0x0B]))
    }

    func testOffFrameIsDistinctFromEveryOtherModesFrame() {
        let frames = CommandableNoiseMode.allCases.compactMap(\.commandFrame)
        XCTAssertEqual(Set(frames).count, frames.count, "every mode's frame should be unique")
    }
}
