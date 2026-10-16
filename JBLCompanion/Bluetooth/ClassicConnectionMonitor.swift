import Foundation
import IOBluetooth
import os.log

@MainActor
protocol ClassicConnectionMonitorDelegate: AnyObject {
    func classicConnectionMonitorDidConnect(_ monitor: ClassicConnectionMonitor)
    func classicConnectionMonitorDidDisconnect(_ monitor: ClassicConnectionMonitor)
}

/// Watches for the classic (BR/EDR) connection state of one specific device, matched only by
/// Bluetooth address (never by name — multiple JBL devices may be paired at once).
///
/// Combines two independent signals: IOBluetoothDevice's real connect/disconnect notifications
/// (the normal, ongoing way state changes are detected), and a ClassicConnectionPoller (see its
/// own doc comment) specifically to catch a device that was already connected before this process
/// started — notifications only fire on a *new* connect event, so a device that's been connected
/// since before launch produces no notification at all. Whichever signal reports the connection
/// first wins; `attach(to:)` is idempotent against the other one arriving late.
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
    private let targetAddress: String

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var connectedDevice: IOBluetoothDevice?
    private var poller: ClassicConnectionPoller?

    weak var delegate: ClassicConnectionMonitorDelegate?

    init(classicAddress: String) {
        self.targetAddress = Self.normalize(classicAddress)
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
            checkIsConnected: { [weak self] in
                guard let self else { return false }
                return IOBluetoothDevice(addressString: self.targetAddress)?.isConnected() ?? false
            },
            onConnected: { [weak self] _ in
                guard let self, let device = IOBluetoothDevice(addressString: self.targetAddress) else { return }
                self.attach(to: device)
            }
        )
        self.poller = poller
        poller.start()
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
            guard Self.normalize(device.addressString ?? "") == self.targetAddress else { return }
            self.logger.info("Classic device connected via notification")
            self.attach(to: device)
        }
    }

    private func attach(to device: IOBluetoothDevice) {
        guard connectedDevice == nil else { return }
        poller?.stop()
        connectedDevice = device
        disconnectNotification = device.register(
            forDisconnectNotification: self,
            selector: #selector(handleDisconnectNotification(notification:device:))
        )
        logger.info("Classic device connected: \(device.addressString ?? "unknown", privacy: .public)")
        delegate?.classicConnectionMonitorDidConnect(self)
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
