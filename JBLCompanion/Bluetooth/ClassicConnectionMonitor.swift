import Foundation
import IOBluetooth
import os.log

@MainActor
protocol ClassicConnectionMonitorDelegate: AnyObject {
    func classicConnectionMonitor(
        _ monitor: ClassicConnectionMonitor, didConnect profile: DeviceProfile,
        address: String, addressConfirmed: Bool
    )
    func classicConnectionMonitorDidDisconnect(_ monitor: ClassicConnectionMonitor)
}

/// Watches for the classic (BR/EDR) connection state of any device matching one of several known
/// DeviceProfiles (DeviceProfileMatcher — primarily by name, never requiring an address match, so
/// an unrecognized unit of a known model is still picked up).
///
/// Combines two independent signals: IOBluetoothDevice's real connect/disconnect notifications
/// (the normal, ongoing way state changes are detected), and a ClassicConnectionPoller (see its
/// own doc comment) specifically to catch a device that was already connected before this process
/// started — notifications only fire on a *new* connect event, so a device that's been connected
/// since before launch produces no notification at all. Whichever signal reports the connection
/// first wins; `attach(to:match:)` is idempotent against the other one arriving late. If a second,
/// different known device connects while one is already attached, `shouldSwitch` makes the newer
/// one the active one — most recently connected wins.
///
/// @MainActor so it can hold the MainActor-isolated poller directly. Confirmed by a real crash
/// (EXC_BREAKPOINT in MainActor.assumeIsolated, 2026-10-16) that IOBluetoothUserNotification
/// callbacks do NOT reliably arrive on the main thread — unlike CBCentralManager's queue: nil,
/// which is an Apple-documented guarantee, classic IOBluetooth has no such contract, and
/// assuming one by analogy was wrong. The callback methods below are `nonisolated` and hop onto
/// the main actor with Task instead of asserting they're already on it.
@MainActor
final class ClassicConnectionMonitor: NSObject {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "ClassicConnectionMonitor")
    private let profiles: [DeviceProfile]

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var connectedDevice: IOBluetoothDevice?
    private var poller: ClassicConnectionPoller?

    weak var delegate: ClassicConnectionMonitorDelegate?

    init(profiles: [DeviceProfile]) {
        self.profiles = profiles
        super.init()
    }

    /// Uppercases and converts dash-separated addresses to colon-separated, so
    /// "00-a4-1c-aa-44-79" and "00:A4:1C:AA:44:79" compare equal. A pure string utility, so it
    /// stays `nonisolated` regardless of the class's own actor — nothing to isolate here, and the
    /// existing tests call it synchronously from a non-isolated context.
    nonisolated static func normalize(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleConnectNotification(notification:device:))
        )

        let poller = ClassicConnectionPoller(
            checkIsConnected: { [weak self] in self?.findConnectedMatchingDevice() != nil },
            onConnected: { [weak self] _ in
                guard let self, let found = self.findConnectedMatchingDevice() else { return }
                self.attach(to: found.device, match: found.match)
            }
        )
        self.poller = poller
        poller.start()
    }

    /// Scans every paired device for the first one that's both actually connected and matches one
    /// of our known profiles — used both by the poller's "already connected at launch" check and,
    /// once it fires, to retrieve the actual matched device (a second pass is simpler and just as
    /// correct as threading the first pass's result through the poller's own Bool-returning API).
    private func findConnectedMatchingDevice() -> (device: IOBluetoothDevice, match: DeviceProfileMatcher.Match)? {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for device in paired {
            guard device.isConnected(), let name = device.name, let address = device.addressString else { continue }
            guard let match = DeviceProfileMatcher.match(name: name, address: address, against: profiles) else { continue }
            return (device, match)
        }
        return nil
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotification?.unregister()
        disconnectNotification = nil
        poller?.stop()
        poller = nil
        connectedDevice = nil
    }

    @objc private nonisolated func handleConnectNotification(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let name = device.name, let address = device.addressString,
                  let match = DeviceProfileMatcher.match(name: name, address: address, against: self.profiles) else { return }
            self.logger.info("Classic device connected via notification, matched profile \(match.profile.displayName, privacy: .public)")
            self.attach(to: device, match: match)
        }
    }

    /// True whenever there's no device currently attached, or the newly-connected device's
    /// address differs from the one we're currently attached to — i.e. whether this connect event
    /// should switch our attention to it. A device reconnecting (or its notification simply
    /// firing twice) while it's already the attached one is a no-op, not a "switch." If two
    /// different known devices are both connected, the one that connects (or reconnects) most
    /// recently always becomes the active one. Pure string comparison, testable without a real
    /// IOBluetoothDevice.
    nonisolated static func shouldSwitch(from currentAddress: String?, to newAddress: String) -> Bool {
        guard let currentAddress else { return true }
        return normalize(currentAddress) != normalize(newAddress)
    }

    private func attach(to device: IOBluetoothDevice, match: DeviceProfileMatcher.Match) {
        let address = device.addressString ?? "unknown"
        guard Self.shouldSwitch(from: connectedDevice?.addressString, to: address) else { return }
        if connectedDevice != nil {
            logger.info("A different classic device connected; switching the active device to \(match.profile.displayName, privacy: .public) (most recently connected wins)")
        }
        poller?.stop()
        disconnectNotification?.unregister()
        connectedDevice = device
        disconnectNotification = device.register(
            forDisconnectNotification: self,
            selector: #selector(handleDisconnectNotification(notification:device:))
        )
        logger.info(
            "Classic device connected: \(address, privacy: .public) matched profile=\(match.profile.displayName, privacy: .public) nameMatch=\(match.profile.classicNameMatch, privacy: .public) addressConfirmed=\(match.addressConfirmed, privacy: .public)"
        )
        delegate?.classicConnectionMonitor(self, didConnect: match.profile, address: address, addressConfirmed: match.addressConfirmed)
    }

    @objc private nonisolated func handleDisconnectNotification(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("Classic device disconnected via notification")
            self.disconnectNotification?.unregister()
            self.disconnectNotification = nil
            self.connectedDevice = nil
            self.delegate?.classicConnectionMonitorDidDisconnect(self)
        }
    }

    /// For "Copy Diagnostics".
    var isConnectedDescription: String {
        connectedDevice != nil ? "connected" : "not connected"
    }
}
