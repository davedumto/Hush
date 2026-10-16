import CoreBluetooth

/// Profile for the JBL Tune 770NC, derived from the Bluetooth recon in ~/jbl-recon.
struct Tune770NCProfile: DeviceProfile {
    let displayName = "JBL Tune 770NC"
    let classicAddress = "00:A4:1C:AA:44:79"

    let bleScanServiceUUID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    let bleExpectedName = "JBL Tune 770NC-LE"

    let batteryServiceUUID = CBUUID(string: "180F")
    let batteryLevelUUID = CBUUID(string: "2A19")

    // Same custom UUID as bleScanServiceUUID — it's both what the LE identity advertises and the
    // vendor ("Airoha RACE") control service that owns the notify/write-without-response pair this
    // phase listens on (ATT handles 0x0053/0x0055 per protocol.md).
    let raceServiceUUID: CBUUID? = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")

    let supportsNoiseControl = true

    // Exactly the three confirmed noise-mode commands (protocol.md / iPad capture), each tied to
    // the RACE service, the write-without-response characteristic, and its full byte frame.
    // TalkThru's frame was never confirmed by a matching event and is deliberately not here.
    let writeAllowlist: [WriteAllowlistEntry] = CommandableNoiseMode.allCases.map { mode in
        WriteAllowlistEntry(
            serviceUUID: CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45"),
            characteristicUUID: CBUUID(string: "43484152-2DAB-3241-6972-6F6861424C45"),
            payload: mode.commandFrame
        )
    }
}
