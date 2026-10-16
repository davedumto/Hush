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
final class ClassicConnectionMonitor: NSObject {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "ClassicConnectionMonitor")
    private let targetAddress: String

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var connectedDevice: IOBluetoothDevice?

    weak var delegate: ClassicConnectionMonitorDelegate?

    init(classicAddress: String) {
        self.targetAddress = Self.normalize(classicAddress)
        super.init()
    }

    /// Uppercases and converts dash-separated addresses to colon-separated, so
    /// "00-a4-1c-aa-44-79" and "00:A4:1C:AA:44:79" compare equal.
    static func normalize(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(handleConnectNotification(notification:device:))
        )
        checkInitialState()
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotification?.unregister()
        disconnectNotification = nil
        connectedDevice = nil
    }

    private func checkInitialState() {
        guard let device = IOBluetoothDevice(addressString: targetAddress),
              device.isConnected() else { return }
        attach(to: device)
    }

    @objc private func handleConnectNotification(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard Self.normalize(device.addressString ?? "") == targetAddress else { return }
        attach(to: device)
    }

    private func attach(to device: IOBluetoothDevice) {
        guard connectedDevice == nil else { return }
        connectedDevice = device
        disconnectNotification = device.register(
            forDisconnectNotification: self,
            selector: #selector(handleDisconnectNotification(notification:device:))
        )
        logger.info("Classic device connected: \(device.addressString ?? "unknown", privacy: .public)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.classicConnectionMonitorDidConnect(self)
        }
    }

    @objc private func handleDisconnectNotification(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        logger.info("Classic device disconnected")
        disconnectNotification?.unregister()
        disconnectNotification = nil
        connectedDevice = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.classicConnectionMonitorDidDisconnect(self)
        }
    }
}
