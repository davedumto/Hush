import Foundation
import os.log

/// Sends an EqualizerPreset's full captured transaction over the RFCOMM link: checks every frame
/// against WriteGuard before sending any of them (a half-sent transaction would leave the
/// headphones in a worse, inconsistent state than refusing outright), then sends them in order
/// with a short gap between each — same shape as the real app's own timing. Unlike
/// NoiseControlCommander, there's no per-call rate limit here: the 12 frames within one
/// transaction are meant to go out close together; `isSending` only prevents two transactions
/// from overlapping each other.
@MainActor
final class EqualizerCommander {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "EqualizerCommander")
    private let writeGuard: WriteGuard
    private weak var transport: RaceWriteTransport?
    private let interFrameGap: TimeInterval

    private(set) var isSending = false

    init(writeGuard: WriteGuard, transport: RaceWriteTransport, interFrameGap: TimeInterval = 0.05) {
        self.writeGuard = writeGuard
        self.transport = transport
        self.interFrameGap = interFrameGap
    }

    /// Sends every frame in `preset.transaction`, in order. Turning the Equalizer off is just
    /// `setPreset(.studio)` — EqualizerPreset's own doc comment covers why there's no separate
    /// "off" transaction to send.
    @discardableResult
    func setPreset(_ preset: EqualizerPreset) async -> Bool {
        guard !isSending else {
            logger.error("Refusing equalizer command: a transaction is already in flight")
            return false
        }
        guard let transport, transport.isReadyForRaceWrites else {
            logger.info("Refusing equalizer command: link not ready")
            return false
        }

        let frames = preset.transaction
        guard frames.allSatisfy({ writeGuard.isAllowed(payload: $0) }) else {
            logger.error("Refusing equalizer command: not every frame is on the write allowlist")
            return false
        }

        isSending = true
        defer { isSending = false }

        for frame in frames {
            guard transport.performRaceWrite(frame) else {
                logger.error("Equalizer transaction write did not go through; aborting mid-transaction")
                return false
            }
            try? await Task.sleep(nanoseconds: UInt64(interFrameGap * 1_000_000_000))
        }

        logger.info("Sent equalizer preset: \(preset.displayName, privacy: .public)")
        return true
    }
}
