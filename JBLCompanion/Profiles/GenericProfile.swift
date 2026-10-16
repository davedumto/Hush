import CoreBluetooth
import IOBluetooth

/// Placeholder fallback profile for an unrecognized/future device. Not wired into the app yet in
/// Phase 1 (only Tune770NCProfile is actually instantiated) — this exists so DeviceProfile has more
/// than one conformer and future multi-device support has somewhere to start.
struct GenericProfile: DeviceProfile {
    let displayName = "Unknown Headphones"
    // Empty on purpose — DeviceProfileMatcher treats an empty classicNameMatch as "never matches"
    // rather than "matches everything" (which `name.contains("")` would otherwise give it).
    let classicNameMatch = ""
    let knownClassicAddress: String? = nil

    let bleScanServiceUUID = CBUUID(string: "1812")
    let bleExpectedName = ""

    let batteryServiceUUID = CBUUID(string: "180F")
    let batteryLevelUUID = CBUUID(string: "2A19")

    let supportsNoiseControl = false
    let allowsRFCOMMWrites = false
    let raceRFCOMMChannelID: BluetoothRFCOMMChannelID = 0

    let writeAllowlist: [WriteAllowlistEntry] = []

    let eventMapVerified = false
    func noiseMode(forEventByte byte: UInt8) -> NoiseMode { .unknown }
}
