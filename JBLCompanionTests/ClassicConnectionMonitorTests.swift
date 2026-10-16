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
}
