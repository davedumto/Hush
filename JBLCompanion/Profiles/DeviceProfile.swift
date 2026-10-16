import CoreBluetooth
import Foundation
import IOBluetooth

/// A single, fully-specified write that WriteGuard is allowed to let through: an exact byte
/// frame. Nothing fuzzy.
struct WriteAllowlistEntry: Equatable {
    let payload: Data
}

/// Everything the app needs to know about one specific headphone model: how to find it over
/// classic Bluetooth and BLE, and what it's allowed to be told.
protocol DeviceProfile {
    var displayName: String { get }

    /// Classic (BR/EDR) Bluetooth address. The only thing ClassicConnectionMonitor matches on, and
    /// what RFCOMMRaceLink looks the device up by.
    var classicAddress: String { get }

    /// The service UUID the device's separate BLE identity advertises; used as a passive scan filter only.
    var bleScanServiceUUID: CBUUID { get }

    /// The exact advertised local name of the BLE identity. The BLE address rotates, so this (plus the
    /// scan filter) is how we recognize the right peripheral.
    var bleExpectedName: String { get }

    var batteryServiceUUID: CBUUID { get }
    var batteryLevelUUID: CBUUID { get }

    var supportsNoiseControl: Bool { get }

    /// The classic RFCOMM channel ID that carries the RACE control protocol (the device's
    /// SDP-advertised "Airoha_APP" service). Noise-mode commands are sent here, not over BLE —
    /// see RFCOMMRaceLink's own doc comment for why.
    var raceRFCOMMChannelID: BluetoothRFCOMMChannelID { get }

    /// WriteGuard's allowlist for this device. Empty means every write is rejected. Expected to be
    /// derived from `isModeVerified`, not hand-maintained separately from it.
    var writeAllowlist: [WriteAllowlistEntry] { get }

    /// Whether the command frame for `mode` is independently verified to actually produce that
    /// mode on real hardware, as opposed to merely being captured from the official app with a
    /// label that was never independently checked. Defaults to false for every mode (see the
    /// protocol extension below) until a conformer explicitly marks one true.
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool
}

extension DeviceProfile {
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool { false }
}
