import Foundation

/// A mode button's five visual states (design/DESIGN_GUIDE.md §4 "Mode buttons"). Hover is
/// deliberately not a sixth case here — it's transient mouse-tracking UI state, not something
/// derivable from `(profile isModeVerified flags, NoiseModeRequestCoordinator state, last
/// confirmed status event)`, so the view layer applies it on top of `.available` on its own.
enum ModeButtonState: Equatable {
    case active
    case available
    case pending
    case disabled
}

/// The status line's dot style (design/DESIGN_GUIDE.md §4 "Status line").
enum StatusLineDotStyle: Equatable {
    /// Confirmed, hardware-verified event map: solid orange, with glow.
    case solidGlow
    /// Pending: hollow orange ring, pulsing.
    case pulsingRing
    /// Confirmed-but-unverified, or timed out: hollow orange ring, not animating.
    case stillRing
}

struct StatusLineContent: Equatable {
    let dotStyle: StatusLineDotStyle
    /// The bold mode name ("ANC", "Ambient", …) — ExtraBold per the guide.
    let modeName: String
    /// The rest of the line ("is currently active", "waiting for headphones…", …).
    let detail: String
}

/// Pure resolver from live state to what each mode button, and the status line beneath them,
/// should show. No view code, no profile/coordinator types — just the handful of primitives those
/// already expose (CLAUDE.md: "Enabled/disabled comes only from the profile's isModeVerified
/// flags. No per-model lists in views.").
enum ModeButtonResolver {
    /// - Parameters:
    ///   - mode: the button being resolved.
    ///   - isModeVerified: `DeviceProfile.isModeVerified(mode)` for the connected device.
    ///   - currentMode: `HeadphoneState.noiseMode` — the last hardware-confirmed mode.
    ///   - pendingMode: `HeadphoneState.pendingNoiseMode`.
    ///
    /// Active is checked before the verified gate, not after: the headphones can report `.off`
    /// on their own (a physical earcup button press — Tune670NCProfile's event map confirms byte
    /// 0x00 for it) even though Off is never independently *commandable* from this app
    /// (`isModeVerified(.off)` is false on every profile, since no Off command frame has ever been
    /// captured). A hardware-reported Off must still show as active, not disabled.
    static func state(
        for mode: CommandableNoiseMode, isModeVerified: Bool, currentMode: NoiseMode,
        pendingMode: CommandableNoiseMode?
    ) -> ModeButtonState {
        if currentMode.commandable == mode { return .active }
        if pendingMode == mode { return .pending }
        if !isModeVerified { return .disabled }
        return .available
    }

    /// Whether a click on this button should actually request a mode change. True only for an
    /// `.available` button, and only while nothing else is already pending — CLAUDE.md/§9.3:
    /// "While one mode is pending, the other buttons ignore clicks," even though those other
    /// buttons keep showing their normal available/active appearance (resolved by `state(for:...)`
    /// above, unaffected by some *other* mode being pending).
    static func isInteractive(
        for mode: CommandableNoiseMode, isModeVerified: Bool, currentMode: NoiseMode,
        pendingMode: CommandableNoiseMode?
    ) -> Bool {
        pendingMode == nil
            && state(for: mode, isModeVerified: isModeVerified, currentMode: currentMode, pendingMode: pendingMode) == .available
    }

    /// - Parameters:
    ///   - currentMode: `HeadphoneState.noiseMode`.
    ///   - pendingMode: `HeadphoneState.pendingNoiseMode`.
    ///   - timedOut: `HeadphoneState.noiseModeConfirmationTimedOut`.
    ///   - eventMapVerified: `HeadphoneState.noiseModeEventMapVerified` — CLAUDE.md: drives
    ///     "(unverified)" alone, never an ack. Only applies to the confirmed line; a timeout's own
    ///     "no response, kept current mode" text doesn't get the suffix (the guide never shows the
    ///     two combined, and the failure here is about the confirmation itself, not the map).
    static func statusLine(
        currentMode: NoiseMode, pendingMode: CommandableNoiseMode?, timedOut: Bool, eventMapVerified: Bool
    ) -> StatusLineContent {
        if let pendingMode {
            return StatusLineContent(
                dotStyle: .pulsingRing, modeName: pendingMode.displayText,
                detail: "waiting for headphones…"
            )
        }
        if timedOut {
            return StatusLineContent(
                dotStyle: .stillRing, modeName: currentMode.displayText,
                detail: "no response, kept current mode"
            )
        }
        // `.unknown` means nothing has ever been confirmed yet (disconnected, or freshly
        // connected before the first status event) — same reasoning NoiseModeStatusText already
        // applies to the "(unverified)" suffix: nothing meaningful to report about headphones
        // that haven't reported anything.
        guard currentMode != .unknown else {
            return StatusLineContent(dotStyle: .stillRing, modeName: currentMode.displayText, detail: "")
        }
        return StatusLineContent(
            dotStyle: eventMapVerified ? .solidGlow : .stillRing,
            modeName: currentMode.displayText,
            detail: eventMapVerified ? "is currently active" : "(unverified)"
        )
    }
}
