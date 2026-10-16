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

    var displayText: String {
        switch self {
        case .off: return "Off"
        case .anc: return "ANC"
        case .ambientAware: return "Ambient Aware"
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
        case .ambientAware: return "Ambient Aware"
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

@Observable
@MainActor
final class HeadphoneState {
    var connection: ConnectionState = .disconnected
    var deviceName: String = ""
    var batteryPercent: Int?
    /// True when the last battery reading was an untrusted 0% (BatteryReadingPolicy), shown as
    /// "--" in the card — distinct from `batteryPercent == nil`, which means no reading at all.
    var batteryPercentIsUnverifiedZero: Bool = false
    var noiseMode: NoiseMode = .unknown
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
