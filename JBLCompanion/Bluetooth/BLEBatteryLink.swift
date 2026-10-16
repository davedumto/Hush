import CoreBluetooth
import Foundation
import os.log

@MainActor
protocol BLEBatteryLinkDelegate: AnyObject {
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateBatteryPercent percent: Int)
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateNoiseMode mode: NoiseMode)
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateRaceLinkStatus status: RaceLinkStatus)
    func bleBatteryLinkDidDisconnect(_ link: BLEBatteryLink)
}

/// Finds the headphone's separate BLE identity (by advertised service UUID + exact local name —
/// never by address, which rotates) once the classic side is connected. Discovers Battery Service,
/// Device Information, and — if the profile has one — the RACE control service, and nothing else.
/// In the RACE service it only ever subscribes to notifications (never reads, never writes);
/// everything it learns about noise mode comes from passively parsing those notifications.
///
/// Runs entirely on the main actor, including every CoreBluetooth delegate callback (the central
/// manager below is created with `queue: nil`, which per Apple's docs dispatches on the main
/// queue). Readiness state (`isPeripheralConnected`, `isRaceNotifySubscribed`,
/// `raceWriteCharacteristic`) used to be mutated from CoreBluetooth's callback queue — a separate
/// background queue this type created itself — while NoiseControlCommander, on the main actor,
/// read it synchronously with no synchronization between the two. That's a data race: nothing
/// guarantees a write on one thread is visible to a read on another without a synchronization
/// point, so the main actor could keep observing stale (never-ready) values. Keeping everything on
/// the main actor removes the race instead of papering over it with a lock.
@MainActor
final class BLEBatteryLink: NSObject {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "BLEBatteryLink")
    private let profile: DeviceProfile
    private let scanTimeout: TimeInterval = 15

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var scanTimeoutWorkItem: DispatchWorkItem?
    private var wantsToScan = false
    private var raceNotifyCharacteristic: CBCharacteristic?
    private var raceWriteCharacteristic: CBCharacteristic?

    /// Owns the RACE notify subscription's retry/pairing state machine — see its own doc comment
    /// for why that logic lives here rather than inline (CoreBluetooth insufficient-encryption
    /// handling needs to be unit-testable, and this class, which owns real CoreBluetooth objects,
    /// can't be).
    private lazy var raceSubscriptionCoordinator: RaceSubscriptionCoordinator = {
        let coordinator = RaceSubscriptionCoordinator(subscriber: self)
        coordinator.onStatusChange = { [weak self] status in
            guard let self else { return }
            self.delegate?.bleBatteryLink(self, didUpdateRaceLinkStatus: status)
        }
        return coordinator
    }()

    /// The most recent readiness tuple actually logged, so `logReadinessIfChanged` only logs on a
    /// real transition instead of on every discovery/notification callback.
    private var lastLoggedReadiness: (connected: Bool, subscribed: Bool, hasWriteChar: Bool)?

    /// Raw bytes (and when) of the last RACE notification received, for "Copy Diagnostics" — kept
    /// even for frames RaceFrameParser doesn't recognize, since an unrecognized frame is itself
    /// useful diagnostic signal.
    private(set) var lastRaceNotificationHex: String?
    private(set) var lastRaceNotificationAt: Date?
    /// Raw bytes (and when) of the last RACE write actually sent over CoreBluetooth.
    private(set) var lastRaceWriteHex: String?
    private(set) var lastRaceWriteAt: Date?

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
        resetRaceState()
    }

    private func resetRaceState() {
        raceNotifyCharacteristic = nil
        raceWriteCharacteristic = nil
        raceSubscriptionCoordinator.handleDisconnect()
        logReadinessIfChanged()
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

    /// Logs the full readiness tuple whenever it actually changes — one line per real transition,
    /// not one per callback, so a diagnostic session stays readable.
    private func logReadinessIfChanged() {
        let current = (connected: isPeripheralConnected, subscribed: isRaceNotifySubscribed, hasWriteChar: raceWriteCharacteristic != nil)
        if let last = lastLoggedReadiness, last == current { return }
        lastLoggedReadiness = current
        logger.info(
            "RACE readiness changed: connected=\(current.connected, privacy: .public) subscribed=\(current.subscribed, privacy: .public) writeChar=\(current.hasWriteChar, privacy: .public)"
        )
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
            logger.info("BLE connected")
            raceSubscriptionCoordinator.handleConnect()
            logReadinessIfChanged()
            var serviceUUIDs = [profile.batteryServiceUUID, CBUUID(string: "180A")]
            let hasRaceService = profile.raceServiceUUID != nil
            if let raceServiceUUID = profile.raceServiceUUID {
                serviceUUIDs.append(raceServiceUUID)
            }
            let discoveredList = hasRaceService ? "180F/180A/RACE" : "180F/180A"
            logger.info("Discovering \(discoveredList, privacy: .public) only")
            peripheral.discoverServices(serviceUUIDs)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            logger.error("BLE connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self.peripheral = nil
            resetRaceState()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        MainActor.assumeIsolated {
            logger.info("BLE peripheral disconnected")
            self.peripheral = nil
            resetRaceState()
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
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil else {
                logger.error("Characteristic discovery failed for \(service.uuid.uuidString, privacy: .public): \(error!.localizedDescription, privacy: .public)")
                return
            }

            if service.uuid == profile.batteryServiceUUID {
                for characteristic in service.characteristics ?? [] where characteristic.uuid == profile.batteryLevelUUID {
                    logger.info("Battery characteristic \(characteristic.uuid.uuidString, privacy: .public) properties=\(Self.describe(characteristic.properties), privacy: .public)")
                    peripheral.readValue(for: characteristic)
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            } else if let raceServiceUUID = profile.raceServiceUUID, service.uuid == raceServiceUUID {
                handleRaceCharacteristics(service.characteristics ?? [], on: peripheral)
            }
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
        raceNotifyCharacteristic = notifyCharacteristic
        raceWriteCharacteristic = writeCandidates[0]
        raceSubscriptionCoordinator.handleWriteCharacteristicDiscovered()
        logReadinessIfChanged()
        logger.info("Subscribing to RACE notify characteristic \(notifyCharacteristic.uuid.uuidString, privacy: .public)")
        peripheral.setNotifyValue(true, for: notifyCharacteristic)
        // Writes themselves only ever happen through NoiseControlCommander, which goes through
        // WriteGuard first — nothing here writes directly.
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard characteristic.uuid == raceNotifyCharacteristic?.uuid else { return }
            logger.info(
                "RACE notify subscription active=\(characteristic.isNotifying, privacy: .public) error=\(error?.localizedDescription ?? "none", privacy: .public)"
            )
            raceSubscriptionCoordinator.handleSubscriptionResult(isNotifying: characteristic.isNotifying, error: error)
            logReadinessIfChanged()
        }
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

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        MainActor.assumeIsolated {
            guard error == nil, let data = characteristic.value else { return }

            if characteristic.uuid == profile.batteryLevelUUID {
                handleBatteryUpdate(data)
            } else if characteristic.uuid == raceNotifyCharacteristic?.uuid {
                handleRaceNotification(data)
            }
        }
    }

    private func handleBatteryUpdate(_ data: Data) {
        guard let byte = data.first else { return }
        let percent = Int(byte)
        logger.info("Battery level: \(percent, privacy: .public)%")
        delegate?.bleBatteryLink(self, didUpdateBatteryPercent: percent)
    }

    private func handleRaceNotification(_ data: Data) {
        lastRaceNotificationHex = data.jblHexString
        lastRaceNotificationAt = Date()

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
                delegate?.bleBatteryLink(self, didUpdateNoiseMode: mode)
            }
        }
    }
}

extension BLEBatteryLink: RaceWriteTransport {
    var isPeripheralConnected: Bool {
        peripheral?.state == .connected
    }

    var isRaceNotifySubscribed: Bool {
        raceSubscriptionCoordinator.isSubscribed
    }

    var isReadyForRaceWrites: Bool {
        isPeripheralConnected && isRaceNotifySubscribed
    }

    var raceWriteCharacteristicUUID: CBUUID? {
        raceWriteCharacteristic?.uuid
    }

    func performRaceWrite(_ payload: Data) -> Bool {
        guard isReadyForRaceWrites, let peripheral, let raceWriteCharacteristic else { return false }
        peripheral.writeValue(payload, for: raceWriteCharacteristic, type: .withoutResponse)
        lastRaceWriteHex = payload.jblHexString
        lastRaceWriteAt = Date()
        return true
    }
}

extension BLEBatteryLink: RaceNotifySubscribing {
    /// Never reads the notify characteristic's value and never writes to it — subscribing is the
    /// only operation this performs here, exactly as on the initial attempt in
    /// handleRaceCharacteristics. There is no write-based workaround for an encryption error; the
    /// only thing that resolves it is the Mac actually pairing/bonding with the headphones.
    func subscribeToRaceNotify() {
        guard let peripheral, let raceNotifyCharacteristic else { return }
        peripheral.setNotifyValue(true, for: raceNotifyCharacteristic)
    }
}

extension BLEBatteryLink {
    /// "domain=... code=... text=..." for the last RACE subscription error, or "none" — for
    /// "Copy Diagnostics".
    var lastSubscriptionErrorDescription: String {
        guard let domain = raceSubscriptionCoordinator.lastErrorDomain,
              let code = raceSubscriptionCoordinator.lastErrorCode,
              let text = raceSubscriptionCoordinator.lastErrorText
        else { return "none" }
        return "domain=\(domain) code=\(code) text=\(text)"
    }

    var raceSubscriptionRetryCount: Int {
        raceSubscriptionCoordinator.retryCount
    }
}
