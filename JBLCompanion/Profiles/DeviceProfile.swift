import CoreBluetooth
import Foundation

/// A single, fully-specified write that WriteGuard is allowed to let through:
/// exact service, exact characteristic, exact byte frame. Nothing fuzzy.
struct WriteAllowlistEntry: Equatable {
    let serviceUUID: CBUUID
    let characteristicUUID: CBUUID
    let payload: Data
}

/// Everything the app needs to know about one specific headphone model:
/// how to find it over classic Bluetooth and BLE, and what it's allowed to be told.
protocol DeviceProfile {
    var displayName: String { get }

    /// Classic (BR/EDR) Bluetooth address. The only thing ClassicConnectionMonitor matches on.
    var classicAddress: String { get }

    /// The service UUID the device's separate BLE identity advertises; used as a passive scan filter only.
    var bleScanServiceUUID: CBUUID { get }

    /// The exact advertised local name of the BLE identity. The BLE address rotates, so this (plus the
    /// scan filter) is how we recognize the right peripheral.
    var bleExpectedName: String { get }

    var batteryServiceUUID: CBUUID { get }
    var batteryLevelUUID: CBUUID { get }

    /// The vendor control ("RACE") service, if this device has one. Its notify/write-without-response
    /// characteristics are discovered dynamically by properties, never hardcoded, so this is only
    /// used as a discovery filter — nil means "this device has no such service, don't look for one."
    var raceServiceUUID: CBUUID? { get }

    var supportsNoiseControl: Bool { get }

    /// WriteGuard's allowlist for this device. Empty means every write is rejected.
    var writeAllowlist: [WriteAllowlistEntry] { get }
}
