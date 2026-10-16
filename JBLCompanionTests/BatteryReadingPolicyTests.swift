import XCTest
@testable import JBLCompanion

final class BatteryReadingPolicyTests: XCTestCase {
    func testZeroIsSuppressedWhenZeroIsNotTrusted() {
        let result = BatteryReadingPolicy.apply(rawPercent: 0, trustsZeroBatteryReading: false)
        XCTAssertNil(result.displayPercent)
        XCTAssertTrue(result.isUnverifiedZero)
    }

    func testZeroPassesThroughWhenZeroIsTrusted() {
        let result = BatteryReadingPolicy.apply(rawPercent: 0, trustsZeroBatteryReading: true)
        XCTAssertEqual(result.displayPercent, 0)
        XCTAssertFalse(result.isUnverifiedZero)
    }

    func testNonZeroAlwaysPassesThroughRegardlessOfTrust() {
        for trusts in [true, false] {
            let result = BatteryReadingPolicy.apply(rawPercent: 42, trustsZeroBatteryReading: trusts)
            XCTAssertEqual(result.displayPercent, 42)
            XCTAssertFalse(result.isUnverifiedZero)
        }
    }

    func testTune670NCProfileDoesNotTrustZeroBattery() {
        XCTAssertFalse(Tune670NCProfile().trustsZeroBatteryReading)
    }

    func testTune770NCProfileTrustsZeroBatteryByDefault() {
        XCTAssertTrue(Tune770NCProfile().trustsZeroBatteryReading)
    }
}
