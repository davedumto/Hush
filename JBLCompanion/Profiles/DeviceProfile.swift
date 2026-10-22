import CoreBluetooth
import Foundation
import IOBluetooth

/// A single, fully-specified write that WriteGuard is allowed to let through: an exact byte
/// frame. Nothing fuzzy.
struct WriteAllowlistEntry: Equatable {
    let payload: Data
}

/// Everything the app needs to know about one specific headphone model: how to find it over
/// classic Bluetooth and BLE, and what it's allowed to be told.
protocol DeviceProfile {
    var displayName: String { get }

    /// Substring matched against a connected classic device's own reported name — the primary
    /// signal DeviceProfileMatcher uses to decide which profile a device belongs to. Primary
    /// because a classic address can differ between units of the same model (or simply not be
    /// known yet), while the device's own advertised name doesn't.
    var classicNameMatch: String { get }

    /// A specific unit's classic (BR/EDR) address, when one happens to be known from recon.
    /// DeviceProfileMatcher only ever checks this as a secondary confirmation signal (surfaced in
    /// logs/diagnostics) — never a requirement for matching, so an unknown or additional unit of
    /// the same model is still recognized by name alone.
    var knownClassicAddress: String? { get }

    /// The service UUID the device's separate BLE identity advertises; used as a passive scan filter only.
    var bleScanServiceUUID: CBUUID { get }

    /// The exact advertised local name of the BLE identity. The BLE address rotates, so this (plus the
    /// scan filter) is how we recognize the right peripheral.
    var bleExpectedName: String { get }

    var batteryServiceUUID: CBUUID { get }
    var batteryLevelUUID: CBUUID { get }

    /// Asset catalog names for this model's headphone product photo (design/DESIGN_GUIDE.md §1
    /// Headphones), nil for a profile with no photographable shot — see the protocol extension's
    /// default below. CollapsedPill falls back to the generic mark when this is nil, per CLAUDE.md:
    /// "Unknown JBL models use the generic mark with no photo."
    var photoAssetNames: HeadphonePhotoAssetNames? { get }

    /// Short model-number text for the card's top-left chip (design/DESIGN_GUIDE.md §4, "[770NC
    /// chip]"), e.g. "770NC". Empty for a profile with no short number to show (the protocol
    /// extension's default) — ExpandedCard hides the chip entirely rather than show an empty
    /// capsule. CLAUDE.md: "Model names, photos and model numbers come from the matched profile."
    var modelNumberText: String { get }

    /// Whether this model's noise control is wired up at all — purely a UI gate (NotchView shows
    /// "Controls not available for this model yet" when false) independent of whether RFCOMM is
    /// opened at all. The RACE channel is opened for ANY matched profile now, to listen for status
    /// (see AppDelegate's classic-connect handler); whether writes are ever attempted through it is
    /// `allowsRFCOMMWrites`'s job, not this one's.
    var supportsNoiseControl: Bool { get }

    /// Whether RFCOMMRaceLink is ever allowed to write a payload for this profile, enforced inside
    /// RFCOMMRaceLink itself (see `performRaceWrite`) — not just by an empty WriteGuard allowlist.
    /// False means every write attempt is refused in code, regardless of what WriteGuard would
    /// otherwise allow; a profile with no verified command frames (like GenericProfile) must set
    /// this false so the channel can still be opened read-only to listen for status.
    var allowsRFCOMMWrites: Bool { get }

    /// Whether a 0% battery reading from this device's hardware is trustworthy as a real "empty"
    /// reading, as opposed to a placeholder/stub value from e.g. unflashed reference firmware.
    /// Defaults to true (see the protocol extension below); a profile overrides it to false only
    /// when it has a concrete reason not to trust a zero reading yet.
    var trustsZeroBatteryReading: Bool { get }

    /// The classic RFCOMM channel ID that carries the RACE control protocol (the device's
    /// SDP-advertised "Airoha_APP" service). Noise-mode commands are sent here, not over BLE —
    /// see RFCOMMRaceLink's own doc comment for why.
    var raceRFCOMMChannelID: BluetoothRFCOMMChannelID { get }

    /// WriteGuard's allowlist for this device. Empty means every write is rejected. Derived from
    /// `isModeVerified` by the protocol extension's default below, not hand-maintained separately
    /// from it — a conformer only needs its own override if its write grammar ever differs from
    /// CommandableNoiseMode.commandFrame's shared one, which none currently do.
    var writeAllowlist: [WriteAllowlistEntry] { get }

    /// Maps a RACE noise-mode event's raw mode byte (RaceEvent.noiseMode's rawByte) to a
    /// NoiseMode. Per-profile, not global, because a different model could in principle assign
    /// different bytes even over an identical wire format — see `eventMapVerified` for whether
    /// this mapping has actually been checked for this exact model, or is only carried over from
    /// a similar one. StandardRaceEventByteMap holds the one hardware-verified mapping known so
    /// far (the 770NC's); a conformer delegates to it rather than duplicating the switch.
    func noiseMode(forEventByte byte: UInt8) -> NoiseMode

    /// Whether `noiseMode(forEventByte:)` has been independently hardware-verified for this exact
    /// model (by sending/observing real events and confirming both the byte and the physical
    /// behavior), as opposed to being a starting assumption carried over from a similar model's
    /// mapping. NotchView appends "(unverified)" to the noise-mode status text while this is
    /// false (NoiseModeStatusText).
    var eventMapVerified: Bool { get }

    /// Whether the command frame for `mode` is independently verified to actually produce that
    /// mode on real hardware, as opposed to merely being captured from the official app with a
    /// label that was never independently checked. Defaults to false for every mode (see the
    /// protocol extension below) until a conformer explicitly marks one true.
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool

    /// The RACE command frame that powers the headphones off remotely — captured 2026-10-22 via
    /// PacketLogger on an iPad running the real JBL app (a BLE ATT write to the RACE write
    /// characteristic), then independently re-verified over the classic RFCOMM bridge
    /// (~/jbl-recon/rfcomm_send_poweroff_670nc.swift): sending it produced the documented ack
    /// (`05 5B 03 00 01 11 00`) and the headphones genuinely powered off. Shared across models the
    /// same way CommandableNoiseMode.commandFrame is (same Airoha chipset/RACE protocol) — nil for
    /// a profile with no known frame at all (the protocol extension's default).
    var powerOffCommandFrame: Data? { get }

    /// Whether `powerOffCommandFrame` has been independently hardware-verified for *this exact*
    /// model, same reasoning as `isModeVerified` — a frame captured/confirmed on one model is not
    /// assumed to work on another until separately tested, even though both currently share the
    /// same chipset family. Defaults to false (the protocol extension below).
    var isPowerOffVerified: Bool { get }

    /// Whether every EqualizerPreset's own `transaction` has been independently hardware-verified
    /// for *this exact* model, same reasoning as `isPowerOffVerified` — each of the 6 presets was
    /// captured and confirmed by ear one at a time (2026-10-22) on the 670NC specifically; nothing
    /// has been tested on another model yet. Unlike noise mode/power-off, the preset data itself
    /// lives on EqualizerPreset directly (not per-profile), since it's the same captured bytes for
    /// every profile that sets this true — this flag only gates whether a profile's own
    /// writeAllowlist includes them.
    var isEqualizerVerified: Bool { get }

    /// Whether DeviceToggle.maxVolumeLimiter's captured frames have been independently
    /// hardware-verified for *this exact* model, same reasoning as `isEqualizerVerified`.
    var isMaxVolumeLimiterVerified: Bool { get }
    /// Whether DeviceToggle.voicePrompt's captured frames have been independently
    /// hardware-verified for *this exact* model, same reasoning as `isEqualizerVerified` — see
    /// DeviceToggle.voicePrompt's own doc comment for why this one's confirmation is weaker.
    var isVoicePromptVerified: Bool { get }
}

extension DeviceProfile {
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool { false }
    var trustsZeroBatteryReading: Bool { true }
    /// Safe by construction: a missing photo only ever falls back to the generic mark, never shows
    /// a wrong one, so this is fine as a silent default (unlike allowsRFCOMMWrites).
    var photoAssetNames: HeadphonePhotoAssetNames? { nil }
    var modelNumberText: String { "" }
    var powerOffCommandFrame: Data? { nil }
    var isPowerOffVerified: Bool { false }
    var isEqualizerVerified: Bool { false }
    var isMaxVolumeLimiterVerified: Bool { false }
    var isVoicePromptVerified: Bool { false }

    /// Every CommandableNoiseMode this profile marks verified, provided it actually has a command
    /// frame (CommandableNoiseMode.commandFrame — Off never will), plus the power-off frame when
    /// independently verified, plus every EqualizerPreset's own transaction frames when verified,
    /// plus each verified DeviceToggle's own on/off frame pair.
    /// compactMap is belt-and-suspenders: isModeVerified(.off) should already be false everywhere.
    var writeAllowlist: [WriteAllowlistEntry] {
        var entries = CommandableNoiseMode.allCases
            .filter { isModeVerified($0) }
            .compactMap { $0.commandFrame.map { WriteAllowlistEntry(payload: $0) } }
        if isPowerOffVerified, let powerOffCommandFrame {
            entries.append(WriteAllowlistEntry(payload: powerOffCommandFrame))
        }
        if isEqualizerVerified {
            entries.append(contentsOf: EqualizerPreset.allCases.flatMap(\.transaction).map { WriteAllowlistEntry(payload: $0) })
        }
        if isMaxVolumeLimiterVerified {
            entries.append(contentsOf: DeviceToggle.maxVolumeLimiter.bothStateFrames.map { WriteAllowlistEntry(payload: $0) })
        }
        if isVoicePromptVerified {
            entries.append(contentsOf: DeviceToggle.voicePrompt.bothStateFrames.map { WriteAllowlistEntry(payload: $0) })
        }
        return entries
    }
}
