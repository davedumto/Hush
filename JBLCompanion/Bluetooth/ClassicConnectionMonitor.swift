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
/// different *model* connects while one is already attached, `shouldSwitch` makes the newer one
/// the active one — most recently connected wins; a redundant notification for the same model
/// (possibly under a different address — see `shouldSwitch`'s own doc comment) is always a no-op.
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
    /// The displayName of whichever profile `connectedDevice` currently matched — see
    /// `shouldSwitch`'s doc comment for why this, not the device's address, is what "switching"
    /// keys on.
    private var connectedProfileDisplayName: String?
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
        connectedProfileDisplayName = nil
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

    /// True whenever there's no profile currently attached, or the newly-matched profile is a
    /// genuinely different model than the one we're currently attached to — i.e. whether this
    /// connect event should switch our attention to it. Deliberately keyed on the matched
    /// *profile*, not the device's address: a real-world observation (2026-10-16, the 670NC) is
    /// that connecting the BLE battery link to an already-classic-connected accessory can trigger
    /// a second IOBluetoothDevice connect notification for the *same physical unit*, resolving to
    /// the same profile by name, but carrying an unrelated/unconfirmed address (likely a
    /// BLE-identity artifact surfaced through the classic notification path) — keying on address
    /// treated that as "a second 670NC connected," tore down the working RFCOMM session, and tried
    /// to reopen it against the bogus address, breaking everything. Keying on the profile instead
    /// means a redundant notification for the same model is always a no-op, never a switch; a
    /// genuinely different model (both headphones actually connected at once) still switches.
    /// Pure string comparison, testable without a real IOBluetoothDevice.
    nonisolated static func shouldSwitch(from currentProfileDisplayName: String?, to newProfileDisplayName: String) -> Bool {
        guard let currentProfileDisplayName else { return true }
        return currentProfileDisplayName != newProfileDisplayName
    }

    private func attach(to device: IOBluetoothDevice, match: DeviceProfileMatcher.Match) {
        let address = device.addressString ?? "unknown"
        guard Self.shouldSwitch(from: connectedProfileDisplayName, to: match.profile.displayName) else {
            logger.info(
                "Ignoring redundant connect notification for \(match.profile.displayName, privacy: .public) (already the active device; this notification's address was \(address, privacy: .public))"
            )
            return
        }
        if connectedDevice != nil {
            logger.info("A different classic device connected; switching the active device to \(match.profile.displayName, privacy: .public) (most recently connected wins)")
        }
        poller?.stop()
        disconnectNotification?.unregister()
        connectedDevice = device
        connectedProfileDisplayName = match.profile.displayName
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
        // Real-world observation (2026-10-17): turning off Bluetooth entirely — rather than just
        // powering off the headphones — tears down the device's several profiles (A2DP, HFP, HID,
        // GATT, SerialPort, ...) close together but not atomically, and IOBluetooth redelivers
        // this same disconnect notification once per underlying teardown event instead of once
        // overall, fast enough that many redeliveries queue up before the first one's async Task
        // even runs. A MainActor-side guard alone (checking `connectedDevice` once hopped over)
        // wasn't enough — it only made each *processed* redelivery cheap, but creating a Task per
        // redelivery was itself still enough volume to peg the main thread at 100% CPU for over a
        // second, freezing the whole app (the tray couldn't even be clicked open). Unregistering
        // `notification` synchronously, immediately, on whatever thread this fires on — before
        // scheduling anything — stops it at the source instead: at most one redelivery can ever
        // reach the Task below. IOBluetoothUserNotification.unregister() is safe to call more than
        // once and off the main thread (this class's own doc comment already establishes these
        // callbacks aren't guaranteed to arrive on the main thread at all).
        notification.unregister()
        Task { @MainActor [weak self] in
            guard let self else { return }
            // `attach(to:match:)` already guards the connect side the same way (`shouldSwitch`,
            // for an analogous redundant-notification bug found 2026-10-16) — this mirrors it for
            // disconnect, as a second line of defense alongside the synchronous unregister above.
            guard self.connectedDevice != nil else { return }
            self.logger.info("Classic device disconnected via notification")
            self.disconnectNotification = nil
            self.connectedDevice = nil
            self.connectedProfileDisplayName = nil
            self.delegate?.classicConnectionMonitorDidDisconnect(self)
        }
    }

    /// For "Copy Diagnostics".
    var isConnectedDescription: String {
        connectedDevice != nil ? "connected" : "not connected"
    }
}
