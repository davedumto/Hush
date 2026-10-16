import XCTest
@testable import JBLCompanion

/// RFCOMMRaceLink always needs a real IOBluetoothDevice/channel to actually become "ready," so
/// these tests can't exercise the whole writeSync path without hardware — what they can verify,
/// hardware-independent, is that writes are refused in code for a profile that doesn't allow them
/// (DeviceProfile.allowsRFCOMMWrites), not merely because the channel never got the chance to
/// open. `performRaceWrite` checks `allowsWrites` before readiness, so a never-ready link already
/// proves nothing on its own — these tests pin that the gate exists and reflects the profile.
@MainActor
final class RFCOMMRaceLinkTests: XCTestCase {
    func testAllowsWritesReflectsThe770NCProfile() {
        let link = RFCOMMRaceLink(profile: Tune770NCProfile(), classicAddress: "00:A4:1C:AA:44:79")
        XCTAssertTrue(link.allowsWrites)
    }

    func testAllowsWritesReflectsThe670NCProfile() {
        // Hardware-verified (~/jbl-recon/rfcomm_send_test_670nc.swift): the 770NC's command frames
        // work identically on the 670NC, confirmed by the user after each send.
        let link = RFCOMMRaceLink(profile: Tune670NCProfile(), classicAddress: "40:72:18:AB:EC:6A")
        XCTAssertTrue(link.allowsWrites)
    }

    func testAllowsWritesIsFalseForAProfileWithNoVerifiedWrites() {
        let link = RFCOMMRaceLink(profile: GenericProfile(), classicAddress: "00:00:00:00:00:00")
        XCTAssertFalse(link.allowsWrites)
    }

    func testPerformRaceWriteRefusesForAnUnwritableProfileRegardlessOfReadiness() {
        let link = RFCOMMRaceLink(profile: GenericProfile(), classicAddress: "00:00:00:00:00:00")
        XCTAssertFalse(link.performRaceWrite(Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x01, 0x00])))
    }
}
