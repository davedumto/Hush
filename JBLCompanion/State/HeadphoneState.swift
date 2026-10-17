import Foundation
import Observation

enum ConnectionState {
    case disconnected
    case connected
}

enum NoiseMode {
    case off
    case anc
    case ambientAware
    case talkThru
    case unknown

    // "Ambient", not "Ambient Aware" — design/DESIGN_GUIDE.md §4/§9.3 uses the short form
    // everywhere (button label, status line, "(unverified)" suffix), and this is the one shared
    // label NoiseModeStatusText/the fallback menu/the mode buttons all read from.
    var displayText: String {
        switch self {
        case .off: return "Off"
        case .anc: return "ANC"
        case .ambientAware: return "Ambient"
        case .talkThru: return "TalkThru"
        case .unknown: return "—"
        }
    }
}

/// The subset of NoiseMode that can actually be requested from the UI. `.unknown` obviously isn't
/// a settable target. Off has no verified (or even captured) command frame at all, so it stays in
/// this set purely so its segment can still be shown, disabled, rather than disappearing — see
/// Tune770NCProfile.isModeVerified and NoiseControlCommander.commandFrame.
enum CommandableNoiseMode: CaseIterable, Hashable {
    case off
    case anc
    case talkThru
    case ambientAware

    var displayText: String {
        switch self {
        case .off: return "Off"
        case .anc: return "ANC"
        case .talkThru: return "TalkThru"
        case .ambientAware: return "Ambient"
        }
    }
}

extension NoiseMode {
    /// nil only for .unknown — there's no commandable equivalent to select for that.
    var commandable: CommandableNoiseMode? {
        switch self {
        case .off: return .off
        case .anc: return .anc
        case .talkThru: return .talkThru
        case .ambientAware: return .ambientAware
        case .unknown: return nil
        }
    }
}

/// Asset catalog names for the collapsed-pill/hero headphone photo, theme-contrast pair —
/// design/DESIGN_GUIDE.md §1 Headphones, §3's "white headphones on the black pill, black
/// headphones on the white pill." Lives here (framework-free, alongside the rest of the
/// profile-derived facts HeadphoneState caches), not in Profiles/, so the UI layer never needs to
/// import CoreBluetooth/IOBluetooth just to read it.
struct HeadphonePhotoAssetNames: Equatable {
    let black: String
    let white: String
}

@Observable
@MainActor
final class HeadphoneState {
    var connection: ConnectionState = .disconnected
    var deviceName: String = ""
    /// Mirrors the connected profile's DeviceProfile.photoAssetNames — nil while disconnected, or
    /// while connected to a matched profile with no photographable product shot (CollapsedPill
    /// falls back to the generic mark; CLAUDE.md: "Unknown JBL models use the generic mark with
    /// no photo").
    var photoAssetNames: HeadphonePhotoAssetNames?
    /// Mirrors the connected profile's DeviceProfile.modelNumberText — empty while disconnected or
    /// for a matched profile with no short number (ExpandedCard hides the chip when empty).
    var modelNumberText: String = ""
    var batteryPercent: Int?
    /// True when the last battery reading was an untrusted 0% (BatteryReadingPolicy), shown as
    /// "--" in the card — distinct from `batteryPercent == nil`, which means no reading at all.
    var batteryPercentIsUnverifiedZero: Bool = false
    var noiseMode: NoiseMode = .unknown
    /// Mirrors the connected profile's DeviceProfile.eventMapVerified — true (no warning) while
    /// disconnected. NoiseModeStatusText appends "(unverified)" to the status line while false.
    var noiseModeEventMapVerified: Bool = true
    var lastUpdated: Date?

    /// Non-nil while a noise-mode command has been sent but not yet confirmed by the headphones.
    /// Deliberately separate from `noiseMode` — the UI must never flip `noiseMode` optimistically.
    var pendingNoiseMode: CommandableNoiseMode?
    /// True if the last pending command's 2s confirmation window elapsed with no matching event.
    var noiseModeConfirmationTimedOut: Bool = false

    #if DEBUG
    /// Populated only by the Debug menu's "Send test frame…" — cleared when a test send starts,
    /// then holds up to the next 5 RACE events received afterward, each as a plain display string.
    /// Lets a mode's real on-device behavior be checked by hand without editing/rebuilding to add
    /// temporary logging.
    var debugRecentEvents: [String] = []
    #endif
}
