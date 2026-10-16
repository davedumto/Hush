import XCTest
@testable import JBLCompanion

final class ClassicConnectionMonitorTests: XCTestCase {
    func testNormalizeConvertsDashesToColons() {
        XCTAssertEqual(ClassicConnectionMonitor.normalize("00-a4-1c-aa-44-79"), "00:A4:1C:AA:44:79")
    }

    func testNormalizeUppercasesColonFormat() {
        XCTAssertEqual(ClassicConnectionMonitor.normalize("00:a4:1c:aa:44:79"), "00:A4:1C:AA:44:79")
    }

    func testNormalizeIsIdempotentOnCanonicalForm() {
        XCTAssertEqual(ClassicConnectionMonitor.normalize("00:A4:1C:AA:44:79"), "00:A4:1C:AA:44:79")
    }

    func testNormalizeOfDifferentDeviceDoesNotMatchTarget() {
        // JBL Charge 4's address, included to guard against ever matching by coincidence.
        XCTAssertNotEqual(ClassicConnectionMonitor.normalize("6C-47-60-A7-31-5B"), "00:A4:1C:AA:44:79")
    }

    // MARK: - shouldSwitch (two-device selection: most recently connected *model* wins)

    func testShouldSwitchWhenNoProfileIsCurrentlyAttached() {
        XCTAssertTrue(ClassicConnectionMonitor.shouldSwitch(from: nil, to: "JBL Tune 770NC"))
    }

    func testShouldNotSwitchWhenTheSameModelReconnects() {
        // Keyed on the matched profile, not the address — a real observed case (the 670NC) is a
        // second connect notification for the same physical unit under an unrelated address (a
        // BLE-identity artifact), which must never be treated as a different device connecting.
        XCTAssertFalse(ClassicConnectionMonitor.shouldSwitch(from: "JBL Tune 670NC", to: "JBL Tune 670NC"))
    }

    func testShouldSwitchWhenADifferentModelConnects() {
        // The 770NC is currently attached; the 670NC connects — most recently connected wins.
        XCTAssertTrue(ClassicConnectionMonitor.shouldSwitch(from: "JBL Tune 770NC", to: "JBL Tune 670NC"))
    }
}
