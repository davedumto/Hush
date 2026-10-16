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

/// The RACE control link's own state — distinct from `ConnectionState`, which only tracks the
/// classic Bluetooth connection. The RACE notify characteristic requires an encrypted BLE link;
/// `needsPairing` means CoreBluetooth reported exactly that (insufficient encryption/
/// authentication), not just "not ready yet" — see RaceSubscriptionCoordinator.
enum RaceLinkStatus {
    case notConnected
    case connecting
    case needsPairing
    case ready

    var displayText: String {
        switch self {
        case .notConnected: return "Not connected"
        case .connecting: return "Connecting"
        case .needsPairing: return "Needs pairing"
        case .ready: return "Ready"
        }
    }

    /// Shown in both the island card and the menu bar dropdown when controls are disabled because
    /// the RACE link needs a fresh BLE pairing — the exact same note in both places (DRY).
    static let needsPairingMessage = "Controls need pairing. Accept the macOS Bluetooth prompt, or put the headphones in pairing mode."
}

@Observable
@MainActor
final class HeadphoneState {
    var connection: ConnectionState = .disconnected
    var deviceName: String = ""
    var batteryPercent: Int?
    var noiseMode: NoiseMode = .unknown
    var lastUpdated: Date?
    var raceLinkStatus: RaceLinkStatus = .notConnected

    /// Non-nil while a noise-mode command has been sent but not yet confirmed by the headphones.
    /// Deliberately separate from `noiseMode` — the UI must never flip `noiseMode` optimistically.
    var pendingNoiseMode: CommandableNoiseMode?
    /// True if the last pending command's 2s confirmation window elapsed with no matching event.
    var noiseModeConfirmationTimedOut: Bool = false
}
