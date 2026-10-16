import XCTest
@testable import JBLCompanion

final class NoiseModeStatusTextTests: XCTestCase {
    func testVerifiedModeHasNoSuffix() {
        XCTAssertEqual(NoiseModeStatusText.format(mode: .anc, eventMapVerified: true), "ANC")
    }

    func testUnverifiedModeGetsASuffix() {
        XCTAssertEqual(NoiseModeStatusText.format(mode: .anc, eventMapVerified: false), "ANC (unverified)")
    }

    func testUnverifiedUnknownModeNeverGetsASuffix() {
        // Nothing meaningful to flag as unverified before any event has ever arrived.
        XCTAssertEqual(NoiseModeStatusText.format(mode: .unknown, eventMapVerified: false), "—")
    }

    func testVerifiedUnknownModeIsUnaffected() {
        XCTAssertEqual(NoiseModeStatusText.format(mode: .unknown, eventMapVerified: true), "—")
    }
}
