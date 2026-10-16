import CoreBluetooth
import IOBluetooth
import XCTest
@testable import JBLCompanion

private struct FakeProfile: DeviceProfile {
    let displayName: String
    let classicNameMatch: String
    let knownClassicAddress: String?

    let bleScanServiceUUID = CBUUID(string: "180F")
    let bleExpectedName = ""
    let batteryServiceUUID = CBUUID(string: "180F")
    let batteryLevelUUID = CBUUID(string: "2A19")
    let supportsNoiseControl = false
    let allowsRFCOMMWrites = false
    let raceRFCOMMChannelID: BluetoothRFCOMMChannelID = 0
    let writeAllowlist: [WriteAllowlistEntry] = []
    let eventMapVerified = false
    func noiseMode(forEventByte byte: UInt8) -> NoiseMode { .unknown }
}

final class DeviceProfileMatcherTests: XCTestCase {
    private let tune770 = Tune770NCProfile()
    private let tune670 = Tune670NCProfile()

    func testMatchesThe770NCByName() {
        let match = DeviceProfileMatcher.match(
            name: "JBL Tune 770NC", address: "00-A4-1C-AA-44-79", against: [tune770, tune670]
        )
        XCTAssertEqual(match?.profile.displayName, "JBL Tune 770NC")
        XCTAssertTrue(match?.addressConfirmed ?? false)
    }

    func testMatchesThe670NCByName() {
        let match = DeviceProfileMatcher.match(
            name: "JBL Tune 670NC", address: "40-72-18-ab-ec-6a", against: [tune770, tune670]
        )
        XCTAssertEqual(match?.profile.displayName, "JBL Tune 670NC")
        XCTAssertTrue(match?.addressConfirmed ?? false)
    }

    func testMatchesThe670NCBLENameVariantToo() {
        // The 670NC's real paired-device name (confirmed via ~/jbl-recon) is exactly "JBL Tune
        // 670NC", not the "-LE" BLE variant, but the substring match should pick it up either way.
        let match = DeviceProfileMatcher.match(
            name: "JBL Tune 670NC-LE", address: "40-72-18-ab-ec-6a", against: [tune770, tune670]
        )
        XCTAssertEqual(match?.profile.displayName, "JBL Tune 670NC")
    }

    func testRejectsTheCharge4() {
        // The Charge 4's real paired name/address, from ~/jbl-recon/classic_670nc_output.txt.
        let match = DeviceProfileMatcher.match(
            name: "JBL Charge 4", address: "6C-47-60-A7-31-5B", against: [tune770, tune670]
        )
        XCTAssertNil(match)
    }

    func testRejectsAnUnrelatedDevice() {
        let match = DeviceProfileMatcher.match(
            name: "AirPods Pro", address: "40-B3-FA-2C-C5-7D", against: [tune770, tune670]
        )
        XCTAssertNil(match)
    }

    func testNameMatchAloneIsSufficientEvenWithoutAnAddressMatch() {
        // A different/unknown physical unit of the same model: name matches, address doesn't —
        // still a match, just with addressConfirmed == false.
        let match = DeviceProfileMatcher.match(
            name: "JBL Tune 670NC", address: "AA-BB-CC-DD-EE-FF", against: [tune670]
        )
        XCTAssertEqual(match?.profile.displayName, "JBL Tune 670NC")
        XCTAssertFalse(match?.addressConfirmed ?? true)
    }

    func testKnownAddressAloneNeverMatchesWithoutANameMatch() {
        // Guards against ever matching by address coincidence alone — the 770NC's own known
        // address, but a name that doesn't contain "770NC" at all.
        let match = DeviceProfileMatcher.match(
            name: "Some Other Speaker", address: "00-A4-1C-AA-44-79", against: [tune770, tune670]
        )
        XCTAssertNil(match)
    }

    func testProfileWithNoKnownAddressNeverConfirmsButStillMatchesByName() {
        let profile = FakeProfile(displayName: "Future Unit", classicNameMatch: "FutureModel", knownClassicAddress: nil)
        let match = DeviceProfileMatcher.match(name: "JBL FutureModel X", address: "11-22-33-44-55-66", against: [profile])
        XCTAssertEqual(match?.profile.displayName, "Future Unit")
        XCTAssertFalse(match?.addressConfirmed ?? true)
    }

    func testEmptyClassicNameMatchNeverMatchesAnything() {
        // GenericProfile's classicNameMatch is "" — guards against name.contains("") (always true)
        // turning it into an accidental catch-all.
        let generic = GenericProfile()
        let match = DeviceProfileMatcher.match(name: "JBL Tune 770NC", address: "00-A4-1C-AA-44-79", against: [generic])
        XCTAssertNil(match)
    }

    func testFirstMatchingProfileInListOrderWins() {
        let match = DeviceProfileMatcher.match(
            name: "JBL Tune 770NC", address: "00-A4-1C-AA-44-79", against: [tune670, tune770]
        )
        // tune670's classicNameMatch ("670NC") isn't contained in "JBL Tune 770NC", so tune770
        // (checked second) is the one that actually matches — list order alone doesn't cause a
        // false match.
        XCTAssertEqual(match?.profile.displayName, "JBL Tune 770NC")
    }
}
