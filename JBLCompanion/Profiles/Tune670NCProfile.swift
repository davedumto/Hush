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

    // No control writes for this model. The Airoha_APP RFCOMM channel (21, SDP-confirmed present
    // in ~/jbl-recon/classic_670nc_output.txt) IS opened for this profile now, to listen for
    // status — see AppDelegate's classic-connect handler — but allowsRFCOMMWrites = false means
    // RFCOMMRaceLink refuses every write attempt in code, and the empty allowlist below is
    // belt-and-suspenders on top of that.
    let supportsNoiseControl = false
    let allowsRFCOMMWrites = false
    let raceRFCOMMChannelID: BluetoothRFCOMMChannelID = 21
    let writeAllowlist: [WriteAllowlistEntry] = []

    // Hardware-verified on the 670NC itself (physical button press, each mode checked in turn):
    // 0x00 Off, 0x01 ANC, 0x09 TalkThru, 0x0A Ambient Aware — identical to the 770NC's event
    // mapping (StandardRaceEventByteMap), so this delegates to it rather than duplicating the
    // switch. All four bytes are now independently confirmed for this model, hence
    // eventMapVerified = true: no "(unverified)" suffix (NoiseModeStatusText).
    let eventMapVerified = true
    func noiseMode(forEventByte byte: UInt8) -> NoiseMode {
        StandardRaceEventByteMap.noiseMode(forEventByte: byte)
    }

    // The one BLE battery read captured during recon came back 0% alongside clearly-placeholder
    // Device Information strings (Model Number "AIROHA-DIS-EXAMPLE", Hardware/Software Revision
    // "Version1.0") — see ~/jbl-recon/670nc_recon.txt. Until a real (non-zero, or independently
    // cross-checked) reading is seen, a 0% reading from this device is treated as unverified
    // rather than a real empty battery — see BatteryReadingPolicy.
    let trustsZeroBatteryReading = false

    // isModeVerified: no override needed — the protocol extension's default (false for every
    // mode) is exactly right, since writeAllowlist is empty anyway.
}
