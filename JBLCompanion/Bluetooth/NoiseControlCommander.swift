import Foundation
import os.log

extension CommandableNoiseMode {
    /// Hardware-verified 2026-10-16 (Ambient/ANC/TalkThru): the user sent each frame and confirmed
    /// both the resulting status event byte and the actual physical audio behavior. The old labels,
    /// carried over unchecked from the original iPad capture (protocol.md §4), had ANC and TalkThru
    /// swapped — the frame previously labeled "Off" (mode byte 0x01) is ANC, and the frame
    /// previously labeled "ANC" (mode byte 0x09) is TalkThru. Ambient's frame (mode byte 0x0A) was
    /// always correct.
    ///
    /// Off went through two disproven hypotheses before this one:
    /// - A 2026-10-22 capture (`ambient-sound-control-off-and-on2.pklg`) looked like a strong
    ///   candidate — a 3-frame burst (features 0x0CD6/0x0009/0x000B, one write) right after a
    ///   status read reported Off — but hardware-testing it
    ///   (`~/jbl-recon/rfcomm_send_off_670nc.swift`) disproved it: the headphones stayed audibly on
    ///   ANC, confirmed by the status event (rawByte 0x01, not 0x00).
    /// - A tightly-scoped capture (`ambient-sound-control.txt`, one Off tap + one ANC re-select,
    ///   nothing else) initially looked like Off sends nothing at all — until a THIRD capture
    ///   (`new-ambient-off-capture.txt`, 2026-10-22: ANC -> tap Off only -> wait 5s, nothing else
    ///   touched) isolated the real frame: the short status-read-shaped command below, `06 0E 00
    ///   0B` with no trailing mode byte (unlike ANC/Ambient/TalkThru's `...0A <byte> <byte>` —
    ///   Off needs no submode value). Hardware-tested standalone
    ///   (`~/jbl-recon/rfcomm_send_off_770nc.swift`) and confirmed: the headphones audibly left ANC
    ///   for a distinct state, not Ambient or TalkThru. Verified 2026-10-22 on the 770NC.
    var commandFrame: Data? {
        switch self {
        case .ambientAware: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x0A, 0x04])
        case .anc: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x01, 0x00])
        case .talkThru: return Data([0x05, 0x5A, 0x06, 0x00, 0x06, 0x0E, 0x00, 0x0A, 0x09, 0x04])
        case .off: return Data([0x05, 0x5A, 0x04, 0x00, 0x06, 0x0E, 0x00, 0x0B])
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
        guard let payload = mode.commandFrame else {
            logger.error("Refusing noise-mode command: no command frame captured for this mode")
            return false
        }
        return send(payload, label: "noise-mode")
    }

    /// Sends `payload` through the exact same ready-check/rate-limit/WriteGuard path as
    /// `setMode` — any other single-shot RACE command (currently just power-off) goes through
    /// here instead of duplicating that logic. `label` is only for the log lines, so a refusal
    /// reads as "Refusing power-off command: ..." rather than a generic, harder-to-trace message.
    @discardableResult
    func send(_ payload: Data, label: String) -> Bool {
        guard let transport, transport.isReadyForRaceWrites else {
            let classicConnected = transport?.isClassicConnected ?? false
            let channelOpen = transport?.isChannelOpen ?? false
            logger.info(
                "Refusing \(label, privacy: .public) command: link not ready: classicConnected=\(classicConnected, privacy: .public) channelOpen=\(channelOpen, privacy: .public)"
            )
            return false
        }

        if let lastWriteAt, now().timeIntervalSince(lastWriteAt) < minimumInterval {
            logger.error("Refusing \(label, privacy: .public) command: minimum write interval not elapsed")
            return false
        }

        guard writeGuard.isAllowed(payload: payload) else {
            logger.error("Refusing \(label, privacy: .public) command: not on the write allowlist")
            return false
        }

        logger.info("Sending \(label, privacy: .public) command: \(payload.jblHexString, privacy: .public)")
        guard transport.performRaceWrite(payload) else {
            logger.error("\(label, privacy: .public) write did not go through")
            return false
        }

        lastWriteAt = now()
        return true
    }
}
