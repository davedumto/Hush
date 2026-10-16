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

    // Listening-only for now: Phase 2a parses noise-mode events but cannot yet control anything.
    let supportsNoiseControl = false

    // Phase 1 performs no writes at all; kept empty until the RACE protocol is independently proven safe.
    let writeAllowlist: [WriteAllowlistEntry] = []
}
