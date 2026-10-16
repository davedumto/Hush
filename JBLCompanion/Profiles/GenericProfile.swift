import CoreBluetooth
import IOBluetooth

/// Placeholder profile for an unrecognized/future device. Not in AppDelegate's actual `profiles`
/// list (only Tune770NCProfile and Tune670NCProfile are instantiated there) — this exists so
/// DeviceProfile has a safe, fully-locked-down conformer to fall back to as more models are added,
/// and so the tests have a genuine "nothing verified at all" baseline distinct from either real
/// model.
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

    // writeAllowlist: no override needed — isModeVerified isn't overridden either, so the
    // protocol extension's default (false for every mode) makes the derived allowlist empty too.

    let eventMapVerified = false
    func noiseMode(forEventByte byte: UInt8) -> NoiseMode { .unknown }
}
