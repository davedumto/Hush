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

    // MARK: - Tune770NCProfile's real allowlist (the three confirmed noise-mode commands)

    private static let raceWriteCharacteristic = CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45")
    private static let raceNotifyCharacteristic = CBUUID(string: "43484152-2DAB-3141-6972-6F6861424C45")

    func testAllowlistAcceptsEachOfTheThreeConfirmedCommands() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        for mode in CommandableNoiseMode.allCases {
            XCTAssertTrue(
                guardInstance.isAllowed(
                    serviceUUID: profile.raceServiceUUID!,
                    characteristicUUID: Self.raceWriteCharacteristic,
                    payload: mode.commandFrame
                ),
                "\(mode) should be on the allowlist"
            )
        }
    }

    func testAllowlistRejectsTheUnconfirmedTalkThruFrame() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        let talkThruFrame = Data([0x05, 0x5A, 0x04, 0x00, 0x06, 0x0E, 0x00, 0x0B])

        XCTAssertFalse(
            guardInstance.isAllowed(
                serviceUUID: profile.raceServiceUUID!,
                characteristicUUID: Self.raceWriteCharacteristic,
                payload: talkThruFrame
            )
        )
    }

    func testAllowlistRejectsASingleByteChangeToAConfirmedCommand() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)
        var tampered = [UInt8](CommandableNoiseMode.anc.commandFrame)
        tampered[tampered.count - 1] ^= 0x01 // flip the last byte

        XCTAssertFalse(
            guardInstance.isAllowed(
                serviceUUID: profile.raceServiceUUID!,
                characteristicUUID: Self.raceWriteCharacteristic,
                payload: Data(tampered)
            )
        )
    }

    func testAllowlistRejectsTheRightBytesOnTheNotifyCharacteristic() {
        let profile = Tune770NCProfile()
        let guardInstance = WriteGuard(allowlist: profile.writeAllowlist)

        XCTAssertFalse(
            guardInstance.isAllowed(
                serviceUUID: profile.raceServiceUUID!,
                characteristicUUID: Self.raceNotifyCharacteristic, // right bytes, wrong characteristic
                payload: CommandableNoiseMode.off.commandFrame
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
