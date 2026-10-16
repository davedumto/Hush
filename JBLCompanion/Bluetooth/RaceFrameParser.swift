import Foundation

/// The four frame types seen on the RACE control channel (protocol.md §2).
enum RaceFrameType: UInt8 {
    case command = 0x5A
    case response = 0x5B
    case event = 0x5C
    case status = 0x5D
}

/// One decoded RACE frame: `05 <type> <len16 LE> <id16 LE> <payload>`.
/// `id` is the first two bytes after the length field; `payload` is whatever's left.
struct RaceFrame: Equatable {
    let type: RaceFrameType
    let id: UInt16
    let payload: Data
}

/// Pure parsing, no I/O. A single BLE notification can carry more than one frame back-to-back
/// (protocol.md §2), so this walks the buffer and returns every complete frame it finds, silently
/// stopping at the first truncated or malformed frame rather than throwing — a corrupt tail should
/// never take down parsing of the frames that came before it.
enum RaceFrameParser {
    /// Minimum bytes for a frame with zero-length payload: sync(1) + type(1) + len16(2) + id16(2).
    private static let minimumFrameBytes = 6

    static func parseFrames(from data: Data) -> [RaceFrame] {
        let bytes = [UInt8](data)
        var frames: [RaceFrame] = []
        var offset = 0

        while offset < bytes.count {
            guard let (frame, consumed) = parseOne(bytes, at: offset) else { break }
            frames.append(frame)
            offset += consumed
        }

        return frames
    }

    private static func parseOne(_ bytes: [UInt8], at offset: Int) -> (RaceFrame, Int)? {
        let remaining = bytes.count - offset
        guard remaining >= minimumFrameBytes else { return nil }
        guard bytes[offset] == 0x05 else { return nil }
        guard let type = RaceFrameType(rawValue: bytes[offset + 1]) else { return nil }

        let len = Int(bytes[offset + 2]) | (Int(bytes[offset + 3]) << 8)
        guard len >= 2 else { return nil } // len must at least cover the id16 field
        let totalFrameBytes = 4 + len
        guard remaining >= totalFrameBytes else { return nil } // truncated — not enough bytes yet

        let id = UInt16(bytes[offset + 4]) | (UInt16(bytes[offset + 5]) << 8)
        let payload = Data(bytes[(offset + 6)..<(offset + totalFrameBytes)])

        return (RaceFrame(type: type, id: id, payload: payload), totalFrameBytes)
    }
}

/// Recognizes the one event type the app understands; everything else is left for the caller to
/// log at debug level and ignore. Only extracts the raw mode byte — mapping it to a NoiseMode is
/// per-profile (DeviceProfile.noiseMode(forEventByte:)), not this parser's job, since a different
/// model could in principle assign different bytes even over an identical wire format.
enum RaceEvent: Equatable {
    case noiseMode(rawByte: UInt8)
}

enum RaceEventRecognizer {
    /// id16 LE for bytes `01 09` (protocol.md §4).
    private static let noiseModeEventID: UInt16 = 0x0901
    private static let noiseModeEventPrefix: [UInt8] = [0x05, 0x00, 0x00]

    static func recognize(_ frame: RaceFrame) -> RaceEvent? {
        guard frame.type == .event, frame.id == noiseModeEventID else { return nil }
        let bytes = [UInt8](frame.payload)
        guard bytes.count == 4, Array(bytes.prefix(3)) == noiseModeEventPrefix else { return nil }
        return .noiseMode(rawByte: bytes[3])
    }
}

/// The one hardware-verified RACE noise-mode event-byte mapping known so far, confirmed on the
/// 770NC. Live-reconfirmed 2026-10-16 over the Airoha_APP RFCOMM channel: the user physically set
/// each mode on the headphones in turn and confirmed it in the same message as the capture,
/// superseding the original iPad-capture-derived mapping (which had Off=0x01, ANC=0x09, and
/// treated 0x00 as unconfirmed/possibly TalkThru). This is the *event* byte mapping only — the
/// *command* bytes used to request a mode (NoiseControlCommander.commandFrame) are a separate,
/// independently-verified question; see that file's own doc comment.
///
/// A DeviceProfile whose own hardware hasn't been independently checked (e.g. Tune670NCProfile)
/// can still delegate its own `noiseMode(forEventByte:)` to this shared map as a starting
/// assumption, rather than duplicating the switch — `eventMapVerified` is what actually records
/// whether that assumption has been confirmed for that model's own hardware.
enum StandardRaceEventByteMap {
    static func noiseMode(forEventByte byte: UInt8) -> NoiseMode {
        switch byte {
        case 0x00: return .off
        case 0x01: return .anc
        case 0x09: return .talkThru
        case 0x0A: return .ambientAware
        default: return .unknown
        }
    }
}
