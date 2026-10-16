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
/// Battery Service only. Noise control moved to RFCOMMRaceLink (see its own doc comment for why);
/// this class no longer touches the RACE service or anything BLE-GATT-write-related at all.
///
/// Runs entirely on the main actor, including every CoreBluetooth delegate callback (the central
/// manager below is created with `queue: nil`, which per Apple's docs dispatches on the main
/// queue) — see RFCOMMRaceLink's doc comment for the same reasoning applied to classic IOBluetooth.
@MainActor
final class BLEBatteryLink: NSObject {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "BLEBatteryLink")
    private let profile: DeviceProfile
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
            central = CBCentralManager(delegate: self, queue: nil)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + scanTimeout, execute: workItem)
    }

    private func handleScanTimeout() {
        guard peripheral == nil, let central, central.isScanning else { return }
        central.stopScan()
        logger.warning("BLE scan timed out without finding \(self.profile.bleExpectedName, privacy: .public)")
    }
}

// CBCentralManagerDelegate/CBPeripheralDelegate are plain (non-Sendable, non-actor-isolated) ObjC
// protocols — the compiler can't see that `queue: nil` above guarantees every callback lands on
// the main queue, so a @MainActor-isolated method can't satisfy these requirements directly
// ("conformance crosses into main actor-isolated code" — an error under Swift 6 language mode).
// `nonisolated` + `MainActor.assumeIsolated` is Apple's documented way to tell the compiler what's
// actually true here: these methods only ever run on the main actor, just not provably so from the
// protocol's own type signature.
extension BLEBatteryLink: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
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
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            guard self.peripheral == nil else { return }
            guard peripheral.name == profile.bleExpectedName else { return }

            scanTimeoutWorkItem?.cancel()
            central.stopScan()
            self.peripheral = peripheral
            logger.info("Found BLE peripheral matching expected name; connecting")
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            peripheral.delegate = self
            logger.info("BLE connected; discovering 180F only")
            peripheral.discoverServices([profile.batteryServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            logger.error("BLE connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self.peripheral = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            logger.info("BLE peripheral disconnected")
            self.peripheral = nil
            delegate?.bleBatteryLinkDidDisconnect(self)
        }
    }
}

extension BLEBatteryLink: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil else {
                logger.error("Service discovery failed: \(error!.localizedDescription, privacy: .public)")
                return
            }
            for service in peripheral.services ?? [] where service.uuid == profile.batteryServiceUUID {
                peripheral.discoverCharacteristics([profile.batteryLevelUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil else {
                logger.error("Characteristic discovery failed for \(service.uuid.uuidString, privacy: .public): \(error!.localizedDescription, privacy: .public)")
                return
            }
            guard service.uuid == profile.batteryServiceUUID else { return }
            for characteristic in service.characteristics ?? [] where characteristic.uuid == profile.batteryLevelUUID {
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, let data = characteristic.value, characteristic.uuid == profile.batteryLevelUUID else { return }
            guard let byte = data.first else { return }
            let percent = Int(byte)
            logger.info("Battery level: \(percent, privacy: .public)%")
            delegate?.bleBatteryLink(self, didUpdateBatteryPercent: percent)
        }
    }
}
