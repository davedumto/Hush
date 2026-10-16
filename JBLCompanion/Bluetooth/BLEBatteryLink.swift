import CoreBluetooth
import Foundation
import os.log

@MainActor
protocol BLEBatteryLinkDelegate: AnyObject {
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateBatteryPercent percent: Int)
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateNoiseMode mode: NoiseMode)
    func bleBatteryLinkDidDisconnect(_ link: BLEBatteryLink)
}

/// Finds the headphone's separate BLE identity (by advertised service UUID + exact local name —
/// never by address, which rotates) once the classic side is connected. Discovers Battery Service,
/// Device Information, and — if the profile has one — the RACE control service, and nothing else.
/// In the RACE service it only ever subscribes to notifications (never reads, never writes);
/// everything it learns about noise mode comes from passively parsing those notifications.
final class BLEBatteryLink: NSObject {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "BLEBatteryLink")
    private let profile: DeviceProfile
    private let queue = DispatchQueue(label: "com.davidejere.JBLCompanion.ble")
    private let scanTimeout: TimeInterval = 15

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var wantsToScan = false
    private var raceNotifyCharacteristicUUID: CBUUID?
    private var raceWriteCharacteristic: CBCharacteristic?
    private var isRaceNotifyActive = false

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
        resetRaceState()
    }

    private func resetRaceState() {
        raceNotifyCharacteristicUUID = nil
        raceWriteCharacteristic = nil
        isRaceNotifyActive = false
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
        peripheral.delegate = self
        var serviceUUIDs = [profile.batteryServiceUUID, CBUUID(string: "180A")]
        let hasRaceService = profile.raceServiceUUID != nil
        if let raceServiceUUID = profile.raceServiceUUID {
            serviceUUIDs.append(raceServiceUUID)
        }
        let discoveredList = hasRaceService ? "180F/180A/RACE" : "180F/180A"
        logger.info("BLE connected; discovering \(discoveredList, privacy: .public) only")
        peripheral.discoverServices(serviceUUIDs)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("BLE connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        self.peripheral = nil
        resetRaceState()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("BLE peripheral disconnected")
        self.peripheral = nil
        resetRaceState()
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
        for service in peripheral.services ?? [] {
            if service.uuid == profile.batteryServiceUUID {
                peripheral.discoverCharacteristics([profile.batteryLevelUUID], for: service)
            } else if let raceServiceUUID = profile.raceServiceUUID, service.uuid == raceServiceUUID {
                // Unlike battery, we don't know the RACE characteristic UUIDs ahead of time —
                // they're picked by properties below, so discover all of them.
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            logger.error("Characteristic discovery failed for \(service.uuid.uuidString, privacy: .public): \(error!.localizedDescription, privacy: .public)")
            return
        }

        if service.uuid == profile.batteryServiceUUID {
            for characteristic in service.characteristics ?? [] where characteristic.uuid == profile.batteryLevelUUID {
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        } else if let raceServiceUUID = profile.raceServiceUUID, service.uuid == raceServiceUUID {
            handleRaceCharacteristics(service.characteristics ?? [], on: peripheral)
        }
    }

    /// Picks the notify and write-without-response characteristics by properties, never by
    /// assumed UUID. If there isn't exactly one of each, logs everything found and stops —
    /// no guessing, no subscribing, no writing.
    private func handleRaceCharacteristics(_ characteristics: [CBCharacteristic], on peripheral: CBPeripheral) {
        for characteristic in characteristics {
            logger.info("RACE characteristic \(characteristic.uuid.uuidString, privacy: .public) properties=\(Self.describe(characteristic.properties), privacy: .public)")
        }

        let notifyCandidates = characteristics.filter { $0.properties.contains(.notify) }
        let writeCandidates = characteristics.filter { $0.properties.contains(.writeWithoutResponse) }

        guard notifyCandidates.count == 1, writeCandidates.count == 1 else {
            logger.error(
                "RACE service has \(notifyCandidates.count, privacy: .public) notify and \(writeCandidates.count, privacy: .public) write-without-response characteristics — expected exactly one of each. Stopping RACE setup rather than guessing."
            )
            return
        }

        let notifyCharacteristic = notifyCandidates[0]
        raceNotifyCharacteristicUUID = notifyCharacteristic.uuid
        raceWriteCharacteristic = writeCandidates[0]
        logger.info("Subscribing to RACE notify characteristic \(notifyCharacteristic.uuid.uuidString, privacy: .public)")
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
        // Writes themselves only ever happen through NoiseControlCommander, which goes through
        // WriteGuard first — nothing here writes directly.
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == raceNotifyCharacteristicUUID else { return }
        isRaceNotifyActive = error == nil && characteristic.isNotifying
        logger.info("RACE notify subscription active=\(self.isRaceNotifyActive, privacy: .public)")
    }

    private static func describe(_ properties: CBCharacteristicProperties) -> String {
        var parts: [String] = []
        if properties.contains(.read) { parts.append("read") }
        if properties.contains(.write) { parts.append("write") }
        if properties.contains(.writeWithoutResponse) { parts.append("writeWithoutResponse") }
        if properties.contains(.notify) { parts.append("notify") }
        if properties.contains(.indicate) { parts.append("indicate") }
        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        if characteristic.uuid == profile.batteryLevelUUID {
            handleBatteryUpdate(data)
        } else if characteristic.uuid == raceNotifyCharacteristicUUID {
            handleRaceNotification(data)
        }
    }

    private func handleBatteryUpdate(_ data: Data) {
        guard let byte = data.first else { return }
        let percent = Int(byte)
        logger.info("Battery level: \(percent, privacy: .public)%")
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.delegate?.bleBatteryLink(self, didUpdateBatteryPercent: percent)
        }
    }

    private func handleRaceNotification(_ data: Data) {
        let frames = RaceFrameParser.parseFrames(from: data)
        for frame in frames {
            guard let event = RaceEventRecognizer.recognize(frame) else {
                logger.info("Unrecognized RACE frame type=\(frame.type.rawValue, privacy: .public) id=\(frame.id, privacy: .public) payload=\(frame.payload.jblHexString, privacy: .public)")
                continue
            }
            switch event {
            case .noiseMode(let mode, let rawByte):
                if rawByte == 0x00 {
                    logger.info("unconfirmed noise mode byte 0x00 (possibly TalkThru)")
                } else {
                    logger.info("Noise mode event: \(String(describing: mode), privacy: .public)")
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.delegate?.bleBatteryLink(self, didUpdateNoiseMode: mode)
                }
            }
        }
    }
}

extension BLEBatteryLink: RaceWriteTransport {
    var isReadyForRaceWrites: Bool {
        peripheral?.state == .connected && isRaceNotifyActive
    }

    var raceWriteCharacteristicUUID: CBUUID? {
        raceWriteCharacteristic?.uuid
    }

    func performRaceWrite(_ payload: Data) -> Bool {
        guard isReadyForRaceWrites, let peripheral, let raceWriteCharacteristic else { return false }
        peripheral.writeValue(payload, for: raceWriteCharacteristic, type: .withoutResponse)
        return true
    }
}
