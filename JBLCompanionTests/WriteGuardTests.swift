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

    func testRaceWriteCharacteristicIsRejectedWithEmptyAllowlist() {
        // Tune770NCProfile's allowlist is empty, so WriteGuard must reject this regardless of
        // payload. Service UUID is Tune770NCProfile.raceServiceUUID; the characteristic UUID is
        // the write-without-response characteristic found during the earlier BLE recon of this
        // device's RACE service (see ~/jbl-recon/ble.swift output).
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        let raceWriteCharacteristic = CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45")

        XCTAssertFalse(
            guardInstance.isAllowed(
                serviceUUID: profile.raceServiceUUID!,
                characteristicUUID: raceWriteCharacteristic,
                payload: Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x09, 0x04]) // ANC-on command
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
