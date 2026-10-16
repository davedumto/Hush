import Foundation
import os.log

extension CommandableNoiseMode {
    /// Hardware-verified 2026-10-16: the user sent each frame and confirmed both the resulting
    /// status event byte and the actual physical audio behavior. The old labels, carried over
    /// unchecked from the original iPad capture (protocol.md §4), had ANC and TalkThru swapped —
    /// the frame previously labeled "Off" (mode byte 0x01) is ANC, and the frame previously
    /// labeled "ANC" (mode byte 0x09) is TalkThru. Ambient's frame (mode byte 0x0A) was always
    /// correct. No command frame has ever been captured for Off at all — `nil` here is not a
    /// placeholder, there is simply nothing to send for it. `Tune770NCProfile.isModeVerified`
    /// reflects exactly this: Ambient, ANC, and TalkThru are verified; Off is not, and can't be
    /// until an actual Off frame is captured.
    var commandFrame: Data? {
        switch self {
        case .ambientAware: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x0A, 0x04])
        case .anc: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x01, 0x00])
        case .talkThru: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x09, 0x04])
        case .off: return nil
        }
    }
}

/// What NoiseControlCommander needs from the RFCOMM transport to actually perform a write,
/// abstracted so it can be unit tested without real IOBluetooth/hardware. RFCOMMRaceLink conforms
/// to this.
@MainActor
protocol RaceWriteTransport: AnyObject {
    /// True only once the classic link is connected AND the Airoha_APP RFCOMM channel (21) is
    /// open and ready to write to.
    var isReadyForRaceWrites: Bool { get }
    /// The classic-connection sub-condition of `isReadyForRaceWrites`, exposed on its own purely
    /// for diagnostics — so a refusal can say exactly which sub-condition is false instead of just
    /// "not ready."
    var isClassicConnected: Bool { get }
    /// The RFCOMM-channel-open sub-condition of `isReadyForRaceWrites`, exposed on its own for the
    /// same reason.
    var isChannelOpen: Bool { get }
    /// Performs the raw write. Caller (NoiseControlCommander) has already run this through
    /// WriteGuard — this only does the RFCOMM call. Returns false if not actually ready.
    func performRaceWrite(_ payload: Data) -> Bool
}

/// Sends noise-mode commands over the RFCOMM link: builds the frame, checks it against WriteGuard,
/// enforces a minimum interval between writes, and never retries on its own. Protocol
/// (NoiseModeSending) so the UI-facing coordinator can be tested against a fake.
@MainActor
protocol NoiseModeSending: AnyObject {
    @discardableResult
    func setMode(_ mode: CommandableNoiseMode) -> Bool
}

@MainActor
final class NoiseControlCommander: NoiseModeSending {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "NoiseControlCommander")
    private let writeGuard: WriteGuard
    private weak var transport: RaceWriteTransport?
    private let minimumInterval: TimeInterval
    private let now: () -> Date
    private var lastWriteAt: Date?

    init(
        writeGuard: WriteGuard,
        transport: RaceWriteTransport,
        minimumInterval: TimeInterval = 0.5,
        now: @escaping () -> Date = Date.init
    ) {
        self.writeGuard = writeGuard
        self.transport = transport
        self.minimumInterval = minimumInterval
        self.now = now
    }

    @discardableResult
    func setMode(_ mode: CommandableNoiseMode) -> Bool {
        guard let transport, transport.isReadyForRaceWrites else {
            let classicConnected = transport?.isClassicConnected ?? false
            let channelOpen = transport?.isChannelOpen ?? false
            logger.info(
                "Refusing noise-mode command: link not ready: classicConnected=\(classicConnected, privacy: .public) channelOpen=\(channelOpen, privacy: .public)"
            )
            return false
        }

        if let lastWriteAt, now().timeIntervalSince(lastWriteAt) < minimumInterval {
            logger.error("Refusing noise-mode command: minimum write interval not elapsed")
            return false
        }

        guard let payload = mode.commandFrame else {
            logger.error("Refusing noise-mode command: no command frame captured for this mode")
            return false
        }
        guard writeGuard.isAllowed(payload: payload) else {
            logger.error("Refusing noise-mode command: not on the write allowlist")
            return false
        }

        logger.info("Sending noise-mode command: \(payload.jblHexString, privacy: .public)")
        guard transport.performRaceWrite(payload) else {
            logger.error("Noise-mode write did not go through")
            return false
        }

        lastWriteAt = now()
        return true
    }
}
