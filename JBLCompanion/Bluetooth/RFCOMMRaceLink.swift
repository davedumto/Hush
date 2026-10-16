import Foundation
import IOBluetooth
import os.log

@MainActor
protocol RFCOMMRaceLinkDelegate: AnyObject {
    func rfcommRaceLink(_ link: RFCOMMRaceLink, didUpdateNoiseMode mode: NoiseMode)
}

/// Carries the RACE control protocol over the classic Airoha_APP RFCOMM channel (21), instead of
/// over BLE GATT. BLE's RACE notify characteristic required an encrypted BLE link this Mac never
/// bonded (CBATTError.insufficientEncryption — see RaceSubscriptionCoordinator's former doc
/// comment, now removed along with it), and the equivalent classic path, ATT-over-BR/EDR on L2CAP
/// PSM 0x001F, was refused outright by the device's own security policy. The Airoha_APP RFCOMM
/// channel needed neither: it opened with no prompt, under the Mac's existing classic pairing, and
/// was live-verified to carry the exact same `05 5x ...` frame grammar (~/jbl-recon,
/// rfcomm_probe.swift and friends).
///
/// Runs entirely on the main actor, matching BLEBatteryLink's own reasoning: IOBluetooth delivers
/// classic callbacks on whatever run loop is current when the request was made, which for an
/// AppKit app's main thread is the main run loop, so there is no separate callback queue to race
/// against like CoreBluetooth's used to have.
@MainActor
final class RFCOMMRaceLink: NSObject {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "RFCOMMRaceLink")
    private let classicAddress: String
    private let channelID: BluetoothRFCOMMChannelID
    private let reassembler = RaceStreamReassembler()

    private var channel: IOBluetoothRFCOMMChannel?
    private var isClassicLinkUp = false
    private var hasAttemptedFirstOpen = false
    private var pendingOpenWorkItem: DispatchWorkItem?

    private(set) var lastOpenIOReturn: String?
    private(set) var recentFrameDescriptions: [String] = []
    private(set) var totalFramesReassembled = 0

    weak var delegate: RFCOMMRaceLinkDelegate?

    init(profile: DeviceProfile) {
        self.classicAddress = profile.classicAddress
        self.channelID = profile.raceRFCOMMChannelID
        super.init()
    }

    // MARK: - Classic connection hooks (driven by AppDelegate via ClassicConnectionMonitorDelegate)

    func handleClassicConnected() {
        isClassicLinkUp = true
        scheduleOpen()
    }

    func handleClassicDisconnected() {
        isClassicLinkUp = false
        pendingOpenWorkItem?.cancel()
        pendingOpenWorkItem = nil
        if let channel {
            _ = channel.close()
        }
        channel = nil
    }

    // MARK: - Opening the channel

    /// A probe (~/jbl-recon/rfcomm_listen.swift) found openRFCOMMChannelAsync's open request can
    /// silently fail to even reach bluetoothd if issued right at process start — a client-side XPC
    /// session warm-up race, not a device-side refusal (the near-identical rfcomm_probe.swift
    /// opened the same channel instantly moments later in the same process). Delaying only the
    /// first attempt gives that session time to finish setting up; later reconnects within the
    /// same long-running app process don't need it again.
    private func scheduleOpen() {
        guard channel == nil else { return }
        pendingOpenWorkItem?.cancel()
        let delay: TimeInterval = hasAttemptedFirstOpen ? 0 : 2
        hasAttemptedFirstOpen = true
        let workItem = DispatchWorkItem { [weak self] in self?.openChannel() }
        pendingOpenWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func openChannel() {
        guard isClassicLinkUp, channel == nil else { return }
        guard let device = IOBluetoothDevice(addressString: classicAddress) else {
            logger.error("Could not construct IOBluetoothDevice for \(self.classicAddress, privacy: .public)")
            return
        }
        var newChannel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelAsync(&newChannel, withChannelID: channelID, delegate: self)
        lastOpenIOReturn = Self.describeIOReturn(result)
        logger.info("openRFCOMMChannelAsync: \(self.lastOpenIOReturn ?? "?", privacy: .public)")
        // The channel itself is only actually usable once rfcommChannelOpenComplete confirms
        // success — newChannel here may be non-nil but not yet open.
    }

    private static func describeIOReturn(_ r: IOReturn) -> String {
        "\(r) (0x\(String(format: "%08X", UInt32(bitPattern: r))))"
    }

    // MARK: - Incoming data

    private func handleIncoming(_ chunk: Data) {
        let frames = reassembler.feed(chunk)
        for frame in frames {
            totalFramesReassembled += 1
            let description = "type=0x\(String(format: "%02X", frame.type.rawValue)) id=0x\(String(format: "%04X", frame.id)) payload=\(frame.payload.jblHexString)"
            recentFrameDescriptions.append(description)
            if recentFrameDescriptions.count > 5 {
                recentFrameDescriptions.removeFirst(recentFrameDescriptions.count - 5)
            }

            guard let event = RaceEventRecognizer.recognize(frame) else {
                logger.info("Unrecognized RACE frame \(description, privacy: .public)")
                continue
            }
            switch event {
            case .noiseMode(let mode, let rawByte):
                logger.info("Noise mode event: \(String(describing: mode), privacy: .public) rawByte=0x\(String(format: "%02X", rawByte), privacy: .public)")
                delegate?.rfcommRaceLink(self, didUpdateNoiseMode: mode)
            }
        }
    }
}

// IOBluetoothRFCOMMChannel's delegate parameter is typed `id`, not a named Swift protocol, so
// these are plain @objc methods (matching the selectors IOBluetooth calls by name), not a formal
// protocol conformance — but they still need `nonisolated` + `MainActor.assumeIsolated` for the
// same reason as BLEBatteryLink's CoreBluetooth delegate methods: the compiler can't see that
// these are only ever invoked on the main run loop, so a @MainActor-isolated method can't be
// called from this unproven-isolation context without asserting it explicitly.
extension RFCOMMRaceLink {
    @objc nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        MainActor.assumeIsolated {
            guard error == kIOReturnSuccess else {
                logger.error("RFCOMM channel open failed: \(Self.describeIOReturn(error), privacy: .public)")
                return
            }
            channel = rfcommChannel
            logger.info("RFCOMM channel open. MTU=\(rfcommChannel.getMTU(), privacy: .public)")
        }
    }

    @objc nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        MainActor.assumeIsolated {
            handleIncoming(Data(bytes: dataPointer, count: dataLength))
        }
    }

    @objc nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated {
            logger.info("RFCOMM channel closed")
            channel = nil
            // Still classic-connected (if we are) — scheduleOpen() will try again on the next
            // classic reconnect notification, or immediately if the link is still up and this
            // closure wasn't caused by handleClassicDisconnected (which already nils `channel`
            // itself and cancels any pending reopen, so this is a no-op in that case).
            if isClassicLinkUp { scheduleOpen() }
        }
    }
}

extension RFCOMMRaceLink: RaceWriteTransport {
    var isClassicConnected: Bool {
        isClassicLinkUp
    }

    var isChannelOpen: Bool {
        channel != nil
    }

    var isReadyForRaceWrites: Bool {
        isClassicConnected && isChannelOpen
    }

    func performRaceWrite(_ payload: Data) -> Bool {
        guard isReadyForRaceWrites, let channel else { return false }
        var bytes = [UInt8](payload)
        let count = UInt16(bytes.count)
        let result = bytes.withUnsafeMutableBytes { ptr -> IOReturn in
            channel.writeSync(ptr.baseAddress, length: count)
        }
        guard result == kIOReturnSuccess else {
            logger.error("RFCOMM writeSync failed: \(Self.describeIOReturn(result), privacy: .public)")
            return false
        }
        return true
    }
}

extension RFCOMMRaceLink {
    /// For "Copy Diagnostics".
    var channelStateDescription: String {
        if !isClassicLinkUp { return "not connected" }
        return isChannelOpen ? "open" : "connecting"
    }

    var reassemblerStatsDescription: String {
        let pending = reassembler.pendingBytes
        return "frames=\(totalFramesReassembled) pendingBytes=\(pending.isEmpty ? "none" : pending.jblHexString)"
    }
}
