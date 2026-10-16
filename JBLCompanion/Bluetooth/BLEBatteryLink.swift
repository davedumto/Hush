import CoreBluetooth
import Foundation
import os.log

@MainActor
protocol BLEBatteryLinkDelegate: AnyObject {
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateBatteryPercent percent: Int)
    func bleBatteryLinkDidDisconnect(_ link: BLEBatteryLink)
}

/// Finds the headphone's separate BLE identity (by advertised service UUID + exact local name —
/// never by address, which rotates) once the classic side is connected, and reads/subscribes to
/// Battery Level only. Discovers nothing beyond 0x180F/0x180A. Performs no writes.
final class BLEBatteryLink: NSObject {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "BLEBatteryLink")
    private let profile: DeviceProfile
    private let queue = DispatchQueue(label: "com.davidejere.JBLCompanion.ble")
    private let scanTimeout: TimeInterval = 15

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var wantsToScan = false

    weak var delegate: BLEBatteryLinkDelegate?

    init(profile: DeviceProfile) {
        self.profile = profile
        super.init()
    }

    func startMonitoring() {
        wantsToScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: queue)
        } else {
            beginScanIfReady()
        }
    }

    func stopMonitoring() {
        wantsToScan = false
        scanTimeoutWorkItem?.cancel()
        scanTimeoutWorkItem = nil
        central?.stopScan()
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
    }

    private func beginScanIfReady() {
        guard wantsToScan, peripheral == nil, let central, central.state == .poweredOn else { return }
        logger.info("Starting BLE scan (service filter), looking for \(self.profile.bleExpectedName, privacy: .public)")
        central.scanForPeripherals(withServices: [profile.bleScanServiceUUID], options: nil)

        let workItem = DispatchWorkItem { [weak self] in
            self?.handleScanTimeout()
        }
        scanTimeoutWorkItem = workItem
        queue.asyncAfter(deadline: .now() + scanTimeout, execute: workItem)
    }

    private func handleScanTimeout() {
        guard peripheral == nil, let central, central.isScanning else { return }
        central.stopScan()
        logger.warning("BLE scan timed out without finding \(self.profile.bleExpectedName, privacy: .public)")
    }
}

extension BLEBatteryLink: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScanIfReady()
        case .unauthorized:
            logger.error("Bluetooth access is unauthorized for this app")
        case .poweredOff:
            logger.warning("Bluetooth is powered off")
        case .unsupported:
            logger.error("BLE unsupported on this Mac")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        guard peripheral.name == profile.bleExpectedName else { return }

        scanTimeoutWorkItem?.cancel()
        central.stopScan()
        self.peripheral = peripheral
        logger.info("Found BLE peripheral matching expected name; connecting")
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("BLE connected; discovering 180F/180A only")
        peripheral.delegate = self
        peripheral.discoverServices([profile.batteryServiceUUID, CBUUID(string: "180A")])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("BLE connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        self.peripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("BLE peripheral disconnected")
        self.peripheral = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.bleBatteryLinkDidDisconnect(self)
        }
    }
}

extension BLEBatteryLink: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            logger.error("Service discovery failed: \(error!.localizedDescription, privacy: .public)")
            return
        }
        for service in peripheral.services ?? [] where service.uuid == profile.batteryServiceUUID {
            peripheral.discoverCharacteristics([profile.batteryLevelUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, service.uuid == profile.batteryServiceUUID else { return }
        for characteristic in service.characteristics ?? [] where characteristic.uuid == profile.batteryLevelUUID {
            peripheral.readValue(for: characteristic)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == profile.batteryLevelUUID,
              let data = characteristic.value,
              let byte = data.first else { return }

        let percent = Int(byte)
        logger.info("Battery level: \(percent, privacy: .public)%")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.bleBatteryLink(self, didUpdateBatteryPercent: percent)
        }
    }
}
