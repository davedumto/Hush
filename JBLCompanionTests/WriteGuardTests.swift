import CoreBluetooth
import XCTest
@testable import JBLCompanion

final class WriteGuardTests: XCTestCase {
    func testEmptyAllowlistRejectsAnyWrite() {
        let guardInstance = WriteGuard(allowlist: [])
        let service = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
        let characteristic = CBUUID(string: "0053")
        let payload = Data([0x05, 0x5A, 0x02, 0x00, 0xD6, 0x0C])

        XCTAssertFalse(guardInstance.isAllowed(serviceUUID: service, characteristicUUID: characteristic, payload: payload))
    }

    func testEmptyAllowlistRejectsEvenAnEmptyPayload() {
        let guardInstance = WriteGuard(allowlist: [])
        XCTAssertFalse(
            guardInstance.isAllowed(
                serviceUUID: CBUUID(string: "180F"),
                characteristicUUID: CBUUID(string: "2A19"),
                payload: Data()
            )
        )
    }

    func testNonEmptyAllowlistStillRejectsNonMatchingWrite() {
        let allowed = WriteAllowlistEntry(
            serviceUUID: CBUUID(string: "180F"),
            characteristicUUID: CBUUID(string: "2A19"),
            payload: Data([0x01])
        )
        let guardInstance = WriteGuard(allowlist: [allowed])

        XCTAssertFalse(
            guardInstance.isAllowed(
                serviceUUID: CBUUID(string: "180F"),
                characteristicUUID: CBUUID(string: "2A19"),
                payload: Data([0x02]) // different payload — not an exact match
            )
        )
    }

    func testExactAllowlistMatchIsAllowed() {
        let entry = WriteAllowlistEntry(
            serviceUUID: CBUUID(string: "180F"),
            characteristicUUID: CBUUID(string: "2A19"),
            payload: Data([0x01])
        )
        let guardInstance = WriteGuard(allowlist: [entry])

        XCTAssertTrue(
            guardInstance.isAllowed(
                serviceUUID: CBUUID(string: "180F"),
                characteristicUUID: CBUUID(string: "2A19"),
                payload: Data([0x01])
            )
        )
    }
}
