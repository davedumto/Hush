import Foundation
import os.log

/// Owns the "click -> pending -> confirmed or timed-out" state machine for noise-mode requests, so
/// that logic is testable independent of AppDelegate (which can't easily be unit tested — it owns
/// real IOBluetooth/CoreBluetooth objects). Never updates HeadphoneState.noiseMode optimistically;
/// only `handleConfirmation` does that, and only once the headphones actually report it.
@MainActor
final class NoiseModeRequestCoordinator {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "NoiseModeRequestCoordinator")
    private let state: HeadphoneState
    private let sender: NoiseModeSending
    private let confirmationTimeout: TimeInterval
    private let scheduleTimeout: (@escaping () -> Void) -> Void

    init(
        state: HeadphoneState,
        sender: NoiseModeSending,
        confirmationTimeout: TimeInterval = 2.0,
        scheduleTimeout: @escaping (@escaping () -> Void) -> Void = { callback in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: callback)
        }
    ) {
        self.state = state
        self.sender = sender
        self.confirmationTimeout = confirmationTimeout
        self.scheduleTimeout = scheduleTimeout
    }

    /// Called when the user picks a mode. Never sends a second command while one is already
    /// pending, and never changes `state.noiseMode` here — only the eventual confirmation (or
    /// timeout) changes what's displayed beyond "pending."
    func requestMode(_ mode: CommandableNoiseMode) {
        guard state.pendingNoiseMode == nil else {
            logger.info("Ignoring noise-mode request while a previous one is still pending")
            return
        }

        guard sender.setMode(mode) else {
            logger.error("Noise-mode command was not sent")
            return
        }

        state.pendingNoiseMode = mode
        state.noiseModeConfirmationTimedOut = false
        scheduleTimeout { [weak self] in
            self?.handleTimeout(for: mode)
        }
    }

    /// Fires after the confirmation window. If a confirmation already arrived (or a different
    /// request superseded this one), `state.pendingNoiseMode` will no longer equal `mode` and this
    /// is a no-op — in particular, this never sends another command on its own.
    func handleTimeout(for mode: CommandableNoiseMode) {
        guard state.pendingNoiseMode == mode else { return }
        logger.error("No confirmation for noise-mode command within \(self.confirmationTimeout, privacy: .public)s")
        state.pendingNoiseMode = nil
        state.noiseModeConfirmationTimedOut = true
    }

    /// Called whenever the headphones report a noise mode (BLEBatteryLinkDelegate). This is the
    /// only place `state.noiseMode` changes.
    func handleConfirmation(_ mode: NoiseMode) {
        state.pendingNoiseMode = nil
        state.noiseModeConfirmationTimedOut = false
        state.noiseMode = mode
        state.lastUpdated = Date()
    }
}
