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

    /// Substring matched against a connected classic device's own reported name — the primary
    /// signal DeviceProfileMatcher uses to decide which profile a device belongs to. Primary
    /// because a classic address can differ between units of the same model (or simply not be
    /// known yet), while the device's own advertised name doesn't.
    var classicNameMatch: String { get }

    /// A specific unit's classic (BR/EDR) address, when one happens to be known from recon.
    /// DeviceProfileMatcher only ever checks this as a secondary confirmation signal (surfaced in
    /// logs/diagnostics) — never a requirement for matching, so an unknown or additional unit of
    /// the same model is still recognized by name alone.
    var knownClassicAddress: String? { get }

    /// The service UUID the device's separate BLE identity advertises; used as a passive scan filter only.
    var bleScanServiceUUID: CBUUID { get }

    /// The exact advertised local name of the BLE identity. The BLE address rotates, so this (plus the
    /// scan filter) is how we recognize the right peripheral.
    var bleExpectedName: String { get }

    var batteryServiceUUID: CBUUID { get }
    var batteryLevelUUID: CBUUID { get }

    /// Whether this model's noise control is wired up at all. Besides describing the device, this
    /// gates whether RFCOMMRaceLink is even allowed to attempt opening the RACE RFCOMM channel on
    /// connect (see AppDelegate's classic-connect handler) — a profile with no verified command
    /// frames must never have that channel opened on its behalf.
    var supportsNoiseControl: Bool { get }

    /// Whether a 0% battery reading from this device's hardware is trustworthy as a real "empty"
    /// reading, as opposed to a placeholder/stub value from e.g. unflashed reference firmware.
    /// Defaults to true (see the protocol extension below); a profile overrides it to false only
    /// when it has a concrete reason not to trust a zero reading yet.
    var trustsZeroBatteryReading: Bool { get }

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
    var trustsZeroBatteryReading: Bool { true }
}
