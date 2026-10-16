import CoreBluetooth
import Foundation
import os.log

extension CommandableNoiseMode {
    /// The exact ATT Write Command value bytes (protocol.md / the iPad capture), confirmed by a
    /// matching noise-mode event for each of these three. TalkThru's frame is deliberately absent —
    /// it was never confirmed and must never be sendable.
    var commandFrame: Data {
        switch self {
        case .ambientAware: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x0A, 0x04])
        case .off: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x01, 0x00])
        case .anc: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x09, 0x04])
        }
    }
}

/// What NoiseControlCommander needs from the BLE layer to actually perform a write, abstracted so
/// it can be unit tested without real CoreBluetooth/hardware. BLEBatteryLink conforms to this.
@MainActor
protocol RaceWriteTransport: AnyObject {
    /// True only once the link is connected AND the RACE notify subscription is confirmed active
    /// (CBPeripheral delegate's didUpdateNotificationStateFor, not just "we called setNotifyValue").
    var isReadyForRaceWrites: Bool { get }
    /// The peripheral-connected sub-condition of `isReadyForRaceWrites`, exposed on its own purely
    /// for diagnostics — so a refusal can say exactly which sub-condition is false instead of just
    /// "not ready."
    var isPeripheralConnected: Bool { get }
    /// The RACE-notify-subscription-confirmed sub-condition of `isReadyForRaceWrites`, exposed on
    /// its own for the same reason.
    var isRaceNotifySubscribed: Bool { get }
    /// The actually-discovered write-without-response characteristic's UUID, or nil if not ready.
    /// Checked against WriteGuard's allowlist rather than assuming it matches what's hardcoded there.
    var raceWriteCharacteristicUUID: CBUUID? { get }
    /// Performs the raw write. Caller (NoiseControlCommander) has already run this through
    /// WriteGuard — this only does the CoreBluetooth call. Returns false if not actually ready.
    func performRaceWrite(_ payload: Data) -> Bool
}

/// Sends noise-mode commands to the RACE write characteristic: builds the frame, checks it against
/// WriteGuard, enforces a minimum interval between writes, and never retries on its own. Protocol
/// (NoiseModeSending) so the UI-facing coordinator can be tested against a fake.
@MainActor
protocol NoiseModeSending: AnyObject {
    @discardableResult
    func setMode(_ mode: CommandableNoiseMode) -> Bool
}

@MainActor
final class NoiseControlCommander: NoiseModeSending {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "NoiseControlCommander")
    private let profile: DeviceProfile
    private let writeGuard: WriteGuard
    private weak var transport: RaceWriteTransport?
    private let minimumInterval: TimeInterval
    private let now: () -> Date
    private var lastWriteAt: Date?

    init(
        profile: DeviceProfile,
        writeGuard: WriteGuard,
        transport: RaceWriteTransport,
        minimumInterval: TimeInterval = 0.5,
        now: @escaping () -> Date = Date.init
    ) {
        self.profile = profile
        self.writeGuard = writeGuard
        self.transport = transport
        self.minimumInterval = minimumInterval
        self.now = now
    }

    @discardableResult
    func setMode(_ mode: CommandableNoiseMode) -> Bool {
        guard let raceServiceUUID = profile.raceServiceUUID else {
            logger.error("No RACE service on this profile; cannot send noise-mode command")
            return false
        }

        guard let transport, transport.isReadyForRaceWrites, let characteristicUUID = transport.raceWriteCharacteristicUUID else {
            let connected = transport?.isPeripheralConnected ?? false
            let subscribed = transport?.isRaceNotifySubscribed ?? false
            let hasWriteChar = transport?.raceWriteCharacteristicUUID != nil
            logger.info(
                "Refusing noise-mode command: link not ready: connected=\(connected, privacy: .public) subscribed=\(subscribed, privacy: .public) writeChar=\(hasWriteChar, privacy: .public)"
            )
            return false
        }

        if let lastWriteAt, now().timeIntervalSince(lastWriteAt) < minimumInterval {
            logger.error("Refusing noise-mode command: minimum write interval not elapsed")
            return false
        }

        let payload = mode.commandFrame
        guard writeGuard.isAllowed(serviceUUID: raceServiceUUID, characteristicUUID: characteristicUUID, payload: payload) else {
            logger.error("Refusing noise-mode command: not on the write allowlist")
            return false
        }

        logger.info("Sending noise-mode command: \(payload.jblHexString, privacy: .public)")
        guard transport.performRaceWrite(payload) else {
            logger.error("Noise-mode write did not go through")
            return false
        }

        lastWriteAt = now()
        return true
    }
}
