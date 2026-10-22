import Foundation

/// A simple on/off device setting — unlike noise mode or Equalizer presets, each state is a single
/// RACE command frame (no multi-frame transaction), but like EqualizerPreset, no RACE event
/// confirms the change (no 5C ever appeared for either toggle in either capture), so the app's own
/// `on` state is local/optimistic only — same limitation, same reasoning as HeadphoneState's own
/// equalizerOn.
enum DeviceToggle {
    /// Hardware-verified 2026-10-22 on the 670NC (`max-volume-limiter-on-and-off.pklg`): the user
    /// toggled this on then off in one isolated capture. The ack itself echoes the trailing value
    /// byte back unchanged (`15 00 00 01` for on, `15 00 00 00` for off), which is a genuine
    /// independent confirmation that byte really is the on/off bit, not just trusting tap order.
    case maxVolumeLimiter
    /// Hardware-verified 2026-10-22 on the 670NC (`voice-prompt-off-and-on.pklg`) — captured off
    /// first, then on, per the filename and the order the user actually performed the taps.
    /// Weaker confirmation than `maxVolumeLimiter`: the ack doesn't echo a distinguishing byte back
    /// (`82 2c 00 09 00`, identical both times), so this trusts the capture's own tap order for
    /// which value is off vs on rather than an independent echo in the response.
    case voicePrompt

    func commandFrame(on: Bool) -> Data {
        switch self {
        case .maxVolumeLimiter:
            return Data([0x05, 0x5A, 0x03, 0x00, 0x15, 0x00, on ? 0x01 : 0x00])
        case .voicePrompt:
            return Data([0x05, 0x5A, 0x05, 0x00, 0x82, 0x2C, 0x09, 0x00, on ? 0x00 : 0xFF])
        }
    }

    /// Both captured states, for `writeAllowlist` — WriteGuard needs the exact frame for whichever
    /// state is being requested, not just one direction.
    var bothStateFrames: [Data] { [commandFrame(on: true), commandFrame(on: false)] }
}
