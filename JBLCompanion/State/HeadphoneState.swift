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

/// The subset of NoiseMode that can actually be commanded (TalkThru's frame is unconfirmed and
/// stays off the write allowlist; .unknown obviously isn't a settable target).
enum CommandableNoiseMode: CaseIterable, Hashable {
    case off
    case anc
    case ambientAware

    var displayText: String {
        switch self {
        case .off: return "Off"
        case .anc: return "ANC"
        case .ambientAware: return "Ambient Aware"
        }
    }
}

extension NoiseMode {
    /// nil for .talkThru/.unknown — there's no commandable equivalent to select for those.
    var commandable: CommandableNoiseMode? {
        switch self {
        case .off: return .off
        case .anc: return .anc
        case .ambientAware: return .ambientAware
        case .talkThru, .unknown: return nil
        }
    }
}

@Observable
@MainActor
final class HeadphoneState {
    var connection: ConnectionState = .disconnected
    var deviceName: String = ""
    var batteryPercent: Int?
    var noiseMode: NoiseMode = .unknown
    var lastUpdated: Date?

    /// Non-nil while a noise-mode command has been sent but not yet confirmed by the headphones.
    /// Deliberately separate from `noiseMode` — the UI must never flip `noiseMode` optimistically.
    var pendingNoiseMode: CommandableNoiseMode?
    /// True if the last pending command's 2s confirmation window elapsed with no matching event.
    var noiseModeConfirmationTimedOut: Bool = false
}
