import CoreBluetooth
import IOBluetooth

/// Profile for the JBL Tune 670NC, derived from the Bluetooth recon in ~/jbl-recon. Every
/// shared-RACE-protocol capability (noise modes, power-off, equalizer, device toggles, event
/// mapping) comes from `AirohaRACECompatible`'s own default implementations — this struct only
/// holds what's genuinely specific to this one device: how to find/identify it, its photo, and its
/// battery-zero-trust quirk.
struct Tune670NCProfile: AirohaRACECompatible {
    let displayName = "JBL Tune 670NC"

    // Matched primarily by name (DeviceProfileMatcher) — this address is only a confirmation
    // signal, read from IOBluetoothDevice.pairedDevices() during read-only recon
    // (~/jbl-recon/classic_670nc_output.txt).
    let classicNameMatch = "670NC"
    let knownClassicAddress: String? = "40:72:18:AB:EC:6A"
    let bleExpectedName = "JBL Tune 670NC-LE"

    // design/DESIGN_GUIDE.md §1 Headphones.
    let photoAssetNames: HeadphonePhotoAssetNames? = HeadphonePhotoAssetNames(black: "Tune670Black", white: "Tune670White")
    let modelNumberText = "670NC"

    // The one BLE battery read captured during recon came back 0% alongside clearly-placeholder
    // Device Information strings (Model Number "AIROHA-DIS-EXAMPLE", Hardware/Software Revision
    // "Version1.0") — see ~/jbl-recon/670nc_recon.txt. Until a real (non-zero, or independently
    // cross-checked) reading is seen, a 0% reading from this device is treated as unverified
    // rather than a real empty battery — see BatteryReadingPolicy. This is the one place this
    // model genuinely differs from AirohaRACECompatible's own default (true).
    let trustsZeroBatteryReading = false
}
