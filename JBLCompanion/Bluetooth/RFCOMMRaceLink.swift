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
/// Runs on the main actor, but — unlike BLEBatteryLink's CoreBluetooth callbacks, which Apple
/// documents as landing on the main queue when `queue: nil` is passed — classic IOBluetooth has no
/// such documented guarantee. A real crash (EXC_BREAKPOINT in MainActor.assumeIsolated,
/// 2026-10-16, in ClassicConnectionMonitor's structurally identical callback) confirmed that
/// assuming one by analogy was wrong: these callbacks can arrive on a background queue. The
/// methods below are `nonisolated` and hop onto the main actor with Task instead of asserting
/// they're already on it.
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

    /// Owns the "a failed open gets retried a few times, a few seconds apart" schedule — see its
    /// own doc comment for why that logic lives here rather than inline.
    private lazy var retryCoordinator = RFCOMMOpenRetryCoordinator(attemptOpen: { [weak self] in self?.openChannel() })

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
        scheduleFirstOpenAttempt()
    }

    func handleClassicDisconnected() {
        isClassicLinkUp = false
        pendingOpenWorkItem?.cancel()
        pendingOpenWorkItem = nil
        retryCoordinator.cancel()
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
    /// very first attempt gives that session time to finish setting up; later reconnects within
    /// the same long-running app process don't need it again. This is a separate concern from
    /// RFCOMMOpenRetryCoordinator's retry-on-failure schedule — this delay happens once, before
    /// the first attempt is even made; the coordinator only acts once an attempt has actually
    /// failed.
    private func scheduleFirstOpenAttempt() {
        guard channel == nil else { return }
        pendingOpenWorkItem?.cancel()
        let delay: TimeInterval = hasAttemptedFirstOpen ? 0 : 2
        hasAttemptedFirstOpen = true
        let workItem = DispatchWorkItem { [weak self] in self?.retryCoordinator.start() }
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
        guard result == kIOReturnSuccess else {
            // The immediate call itself failed (request never even queued) — treat it exactly
            // like an eventual rfcommChannelOpenComplete failure so the same retry schedule
            // applies either way.
            retryCoordinator.handleOpenFailure()
            return
        }
        // Success here only means the request was queued; the channel becomes usable (or the
        // attempt is confirmed failed) once rfcommChannelOpenComplete reports back.
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
// protocol conformance. They're `nonisolated` and hop onto the main actor with Task — see this
// file's own doc comment for why MainActor.assumeIsolated is unsafe here.
extension RFCOMMRaceLink {
    @objc nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard error == kIOReturnSuccess else {
                self.logger.error("RFCOMM channel open failed: \(Self.describeIOReturn(error), privacy: .public)")
                self.retryCoordinator.handleOpenFailure()
                return
            }
            self.channel = rfcommChannel
            self.retryCoordinator.handleOpenSuccess()
            self.logger.info("RFCOMM channel open. MTU=\(rfcommChannel.getMTU(), privacy: .public)")
        }
    }

    @objc nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        // Copied synchronously, before the hop below — dataPointer is only valid for the duration
        // of this callback, not for whenever the deferred Task eventually gets to run. Data's own
        // initializer copies eagerly, so this is a real, owned copy, safe to carry across actors.
        let chunk = Data(bytes: dataPointer, count: dataLength)
        Task { @MainActor [weak self] in
            self?.handleIncoming(chunk)
        }
    }

    @objc nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.logger.info("RFCOMM channel closed")
            self.channel = nil
            // Still classic-connected (if we are) — start a fresh open attempt right away. If
            // this closure was actually caused by handleClassicDisconnected, isClassicLinkUp is
            // already false by the time this runs, so it's a no-op (that path already nils
            // `channel` and cancels retryCoordinator itself).
            if self.isClassicLinkUp { self.retryCoordinator.start() }
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

    var openRetryCount: Int {
        retryCoordinator.retryCount
    }

    var reassemblerStatsDescription: String {
        let pending = reassembler.pendingBytes
        return "frames=\(totalFramesReassembled) pendingBytes=\(pending.isEmpty ? "none" : pending.jblHexString)"
    }
}
