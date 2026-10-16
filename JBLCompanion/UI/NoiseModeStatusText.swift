import Foundation

/// Pure formatting for the noise-mode status line (NotchView's card, the fallback menu, and the
/// MenuBarExtra dropdown): appends "(unverified)" when the connected device's event-byte map
/// (DeviceProfile.eventMapVerified) hasn't been hardware-confirmed yet, so an assumed-but-
/// unconfirmed mapping is never shown with the same confidence as a verified one. Never appends it
/// to `.unknown` ("—") — there's nothing meaningful to flag as unverified before any event arrives.
enum NoiseModeStatusText {
    static func format(mode: NoiseMode, eventMapVerified: Bool) -> String {
        guard !eventMapVerified else { return mode.displayText }
        switch mode {
        case .unknown: return mode.displayText
        default: return "\(mode.displayText) (unverified)"
        }
    }
}
