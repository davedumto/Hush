import CoreBluetooth
import IOBluetooth

/// A profile for a device confirmed to share the Airoha RACE protocol family verified hardware
/// against the 670NC and 770NC — same chipset, same vendor GATT bridge, same classic RFCOMM
/// channel/command grammar, same 0x5A/0x5B/0x5C/0x5D frame format. Owner directive, 2026-10-22:
/// "we have to open this implementation so any headphone that is compatible can just adopt it...
/// I hate this thing that we will implement something for 670 and I have to tell you to implement
/// it for 770NC as well" — every shared-protocol capability lives HERE, once, as a default.
/// Conforming to this protocol is what makes a profile inherit all of it automatically; a new
/// capability only needs to be added to this one extension, never copy-pasted per model again.
///
/// A profile only overrides one of these defaults when it's genuinely NOT the same for that model
/// — e.g. a different event-byte mapping, or a command this exact model is independently NOT
/// verified for yet. Everything else (identity: name matching, addresses, photos, model number
/// text) stays on the conforming struct itself, since that's genuinely per-device, not
/// per-protocol.
protocol AirohaRACECompatible: DeviceProfile {}

extension AirohaRACECompatible {
    // Every Airoha RACE bridge found so far uses the same vendor GATT service/characteristics and
    // the same "Airoha_APP" SDP-advertised RFCOMM channel (~/jbl-recon/sdp_output_rfcomm_check.txt).
    var bleScanServiceUUID: CBUUID { CBUUID(string: "5052494D-2DAB-0341-6972-6F6861424C45") }
    var batteryServiceUUID: CBUUID { CBUUID(string: "180F") }
    var batteryLevelUUID: CBUUID { CBUUID(string: "2A19") }
    var raceRFCOMMChannelID: BluetoothRFCOMMChannelID { 21 }

    var supportsNoiseControl: Bool { true }
    var allowsRFCOMMWrites: Bool { true }

    // Hardware-verified (RaceFrameParser.StandardRaceEventByteMap's own doc comment): 0x00 Off,
    // 0x01 ANC, 0x09 TalkThru, 0x0A Ambient Aware — independently reconfirmed on both the 770NC
    // (original) and the 670NC (physical button press, each mode checked in turn).
    var eventMapVerified: Bool { true }
    func noiseMode(forEventByte byte: UInt8) -> NoiseMode {
        StandardRaceEventByteMap.noiseMode(forEventByte: byte)
    }

    // Hardware-verified (NoiseControlCommander.commandFrame's own doc comment): Ambient, ANC, and
    // TalkThru each produced the matching status event AND the matching physical/audible mode
    // change. Off's own frame was the hardest of the four to find — two disproven hypotheses
    // before the real one, finally confirmed 2026-10-22 standalone on the 770NC
    // (~/jbl-recon/rfcomm_send_off_770nc.swift) — but once a command frame is confirmed correct
    // for this shared protocol, it's correct for every conformer, not just the one it happened to
    // be tested on first.
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool { true }

    // Hardware-verified directly on the 670NC, twice over (captured via PacketLogger on an iPad
    // running the real JBL app, then independently re-sent over the classic RFCOMM channel —
    // ~/jbl-recon/rfcomm_send_poweroff_670nc.swift) — produced the documented ack and the
    // headphones genuinely powered off.
    var powerOffCommandFrame: Data? { Data([0x05, 0x5A, 0x04, 0x00, 0x01, 0x11, 0x18, 0x00]) }
    var isPowerOffVerified: Bool { true }

    // Hardware-verified on the 670NC, one preset at a time, 2026-10-22: each of the 6 presets
    // (EqualizerPreset's own doc comment) was captured from its own isolated single-tap session,
    // replayed over classic RFCOMM, and confirmed by ear.
    var isEqualizerVerified: Bool { true }

    // Hardware-verified on the 670NC, 2026-10-22 (DeviceToggle.maxVolumeLimiter/.voicePrompt's own
    // doc comments cover each capture and its confirmation strength).
    var isMaxVolumeLimiterVerified: Bool { true }
    var isVoicePromptVerified: Bool { true }
}
