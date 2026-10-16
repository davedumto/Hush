import Foundation

/// Reassembles the RACE frame stream out of a continuous byte stream. Unlike a single BLE
/// notification (already one discrete packet), RFCOMM has no built-in message framing — a
/// 667-byte MTU read can split one frame across two callbacks, or carry two or more frames
/// back-to-back in a single one, with no guarantee either way. Keeps whatever's left over (a
/// frame still arriving) buffered until a later feed completes it.
///
/// Reuses RaceFrameParser as the single source of truth for frame boundaries rather than
/// reimplementing the grammar here — each frame it returns has an on-wire size of exactly
/// `6 + payload.count` (sync + type + len16 + id16, then the payload the len16 field covers), so
/// that's how much of the buffer each one accounts for.
final class RaceStreamReassembler {
    private var buffer = Data()

    /// Feeds in newly-received bytes and returns every complete frame now available, in order.
    /// Any trailing partial frame stays buffered for a later call to complete.
    func feed(_ chunk: Data) -> [RaceFrame] {
        buffer.append(chunk)
        let frames = RaceFrameParser.parseFrames(from: buffer)
        let consumed = frames.reduce(0) { $0 + 6 + $1.payload.count }
        buffer.removeFirst(consumed)
        return frames
    }

    /// Whatever's left in the buffer that hasn't formed a complete frame yet — empty almost all
    /// the time; non-empty only mid-frame, or if the stream ever desynced (RaceFrameParser stops
    /// at the first malformed frame rather than guessing a resync, so bytes that don't start a
    /// valid frame stay here rather than being silently dropped). Exposed so a caller can flag a
    /// partial frame left hanging, e.g. when the channel closes.
    var pendingBytes: Data {
        buffer
    }
}
