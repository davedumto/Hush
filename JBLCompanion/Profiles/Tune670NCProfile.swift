import CoreBluetooth
import IOBluetooth

/// Profile for the JBL Tune 670NC, derived from the Bluetooth recon in ~/jbl-recon.
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

    // Hardware-verified directly on the 670NC (~/jbl-recon/rfcomm_send_test_670nc.swift): sending
    // the 770NC's ANC (0A 01 00), TalkThru (0A 09 04), and Ambient Aware (0A 0A 04) command frames
    // each produced the matching status event AND the matching physical/audible mode change,
    // confirmed by the user after every send. Off is not: like the 770NC, no Off command frame has
    // ever been captured for this model either.
    let supportsNoiseControl = true
    let allowsRFCOMMWrites = true
    let raceRFCOMMChannelID: BluetoothRFCOMMChannelID = 21

    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool {
        switch mode {
        case .ambientAware, .anc, .talkThru: return true
        case .off: return false
        }
    }

    // writeAllowlist: no override needed — the protocol extension's default, derived from
    // isModeVerified above, is exactly right.

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
}
