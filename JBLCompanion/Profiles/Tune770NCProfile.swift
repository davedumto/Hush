import CoreBluetooth

/// Profile for the JBL Tune 770NC, derived from the Bluetooth recon in ~/jbl-recon.
struct Tune770NCProfile: DeviceProfile {
    let displayName = "JBL Tune 770NC"
    let classicAddress = "00:A4:1C:AA:44:79"

    let bleScanServiceUUID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    let bleExpectedName = "JBL Tune 770NC-LE"

    let batteryServiceUUID = CBUUID(string: "180F")
    let batteryLevelUUID = CBUUID(string: "2A19")

    let supportsNoiseControl = false

    // Phase 1 performs no writes at all; kept empty until the RACE protocol is independently proven safe.
    let writeAllowlist: [WriteAllowlistEntry] = []
}
