import XCTest
@testable import JBLCompanion

/// Covers DeviceProfile.noiseMode(forEventByte:)/eventMapVerified/allowsRFCOMMWrites for the two
/// real profiles — the per-profile event map and write-safety gate added alongside RFCOMM
/// listening for the 670NC.
final class DeviceProfileEventMapTests: XCTestCase {
    private let allKnownBytes: [UInt8] = [0x00, 0x01, 0x09, 0x0A, 0xFF]

    // MARK: - 770NC: hardware-verified, unchanged

    func testTune770NCProfileEventMapIsVerified() {
        XCTAssertTrue(Tune770NCProfile().eventMapVerified)
    }

    func testTune770NCProfileEventMapMatchesTheStandardMap() {
        let profile = Tune770NCProfile()
        for byte in allKnownBytes {
            XCTAssertEqual(profile.noiseMode(forEventByte: byte), StandardRaceEventByteMap.noiseMode(forEventByte: byte))
        }
    }

    func testTune770NCProfileAllowsRFCOMMWrites() {
        XCTAssertTrue(Tune770NCProfile().allowsRFCOMMWrites)
    }

    // MARK: - 670NC: hardware-verified on its own unit (physical button press, every mode)

    func testTune670NCProfileEventMapIsVerified() {
        XCTAssertTrue(Tune670NCProfile().eventMapVerified)
    }

    func testTune670NCProfileEventMapMatchesThe770NC() {
        let profile = Tune670NCProfile()
        for byte in allKnownBytes {
            XCTAssertEqual(profile.noiseMode(forEventByte: byte), StandardRaceEventByteMap.noiseMode(forEventByte: byte))
        }
    }

    func testTune670NCProfileAllowsRFCOMMWrites() {
        // Hardware-verified: ~/jbl-recon/rfcomm_send_test_670nc.swift sent the 770NC's ANC,
        // TalkThru, and Ambient Aware command frames directly to the 670NC and the user confirmed
        // each one's real physical effect.
        XCTAssertTrue(Tune670NCProfile().allowsRFCOMMWrites)
    }

    // MARK: - GenericProfile: safe placeholder defaults

    func testGenericProfileEventMapIsUnverifiedAndMapsEverythingToUnknown() {
        let profile = GenericProfile()
        XCTAssertFalse(profile.eventMapVerified)
        for byte in allKnownBytes {
            XCTAssertEqual(profile.noiseMode(forEventByte: byte), .unknown)
        }
    }

    func testGenericProfileNeverAllowsRFCOMMWrites() {
        XCTAssertFalse(GenericProfile().allowsRFCOMMWrites)
    }
}
