import Foundation
import os.log

extension CommandableNoiseMode {
    /// UNVERIFIED against live behavior. These three byte sequences and their mode labels came
    /// from the iPad capture of the official app (protocol.md §4) — command sent, then the
    /// resulting status event's last byte, assumed (not proven) to echo the command's own mode
    /// byte back. Live re-testing on 2026-10-16 (protocol.md's correction, same section) showed
    /// the *event* mapping that assumption was built on is wrong: the live-confirmed event bytes
    /// are Off=0x00, ANC=0x01, TalkThru=0x09, Ambient=0x0A, not Off=0x01/ANC=0x09 as the original
    /// capture's own labels claimed.
    ///
    /// Hypothesis, not yet checked: if the command byte really does equal the event byte it
    /// produces, the "Off" command below (mode byte 0x01) actually sets ANC, and the "ANC" command
    /// (mode byte 0x09) actually sets TalkThru. Only Ambient's command is trustworthy, because its
    /// mode byte (0x0A) and the live-confirmed Ambient event byte agree, and the label matches.
    /// `Tune770NCProfile.isModeVerified` gates on exactly this — Off and ANC stay unenabled until
    /// someone confirms what their commands actually do on real hardware, e.g. via the Debug
    /// menu's "Send test frame…" item.
    var commandFrame: Data {
        switch self {
        case .ambientAware: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x0A, 0x04])
        case .off: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x01, 0x00])
        case .anc: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x09, 0x04])
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

        let payload = mode.commandFrame
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
