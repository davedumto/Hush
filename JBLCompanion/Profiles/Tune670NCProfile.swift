import CoreBluetooth
import IOBluetooth

/// Profile for the JBL Tune 670NC: battery and connection status only, matching the read-only
/// recon in ~/jbl-recon (classic_670nc.swift, ble_670nc.swift, 670nc_recon.txt). No control writes
/// yet — see the fields below for exactly what's deliberately disabled and why.
struct Tune670NCProfile: DeviceProfile {
    let displayName = "JBL Tune 670NC"

    // Matched primarily by name (DeviceProfileMatcher) — this address is only a confirmation
    // signal, read from IOBluetoothDevice.pairedDevices() during read-only recon
    // (~/jbl-recon/classic_670nc_output.txt).
    let classicNameMatch = "670NC"
    let knownClassicAddress: String? = "40:72:18:AB:EC:6A"

    // SDP-confirmed: the 670NC advertises the identical custom BLE scan UUID as the 770NC
    // (~/jbl-recon/classic_670nc_output.txt, record 13) — same vendor GATT bridge, different unit.
    let bleScanServiceUUID = CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45")
    let bleExpectedName = "JBL Tune 670NC-LE"

    let batteryServiceUUID = CBUUID(string: "180F")
    let batteryLevelUUID = CBUUID(string: "2A19")

    // No control writes for this model yet. The Airoha_APP RFCOMM channel (21) is SDP-confirmed
    // present (~/jbl-recon/classic_670nc_output.txt), but supportsNoiseControl = false means
    // AppDelegate never tells RFCOMMRaceLink to open it for this profile — RFCOMM listening for
    // the 670NC is deliberately deferred to a later branch once hardware-captured frames are
    // verified. The empty allowlist below is belt-and-suspenders: even a stray write attempt
    // would still be rejected.
    let supportsNoiseControl = false
    let raceRFCOMMChannelID: BluetoothRFCOMMChannelID = 21
    let writeAllowlist: [WriteAllowlistEntry] = []

    // The one BLE battery read captured during recon came back 0% alongside clearly-placeholder
    // Device Information strings (Model Number "AIROHA-DIS-EXAMPLE", Hardware/Software Revision
    // "Version1.0") — see ~/jbl-recon/670nc_recon.txt. Until a real (non-zero, or independently
    // cross-checked) reading is seen, a 0% reading from this device is treated as unverified
    // rather than a real empty battery — see BatteryReadingPolicy.
    let trustsZeroBatteryReading = false

    // isModeVerified: no override needed — the protocol extension's default (false for every
    // mode) is exactly right, since writeAllowlist is empty anyway.
}
