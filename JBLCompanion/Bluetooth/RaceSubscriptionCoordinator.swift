import CoreBluetooth
import Foundation
import os.log

/// What RaceSubscriptionCoordinator needs from the BLE layer to (re)issue a RACE notify
/// subscription, abstracted so the retry/pairing state machine below is unit-testable without
/// real CoreBluetooth/hardware. BLEBatteryLink conforms to this.
@MainActor
protocol RaceNotifySubscribing: AnyObject {
    func subscribeToRaceNotify()
}

/// Owns the "subscribe, maybe hit insufficient encryption, retry, ready or exhausted" state
/// machine for the RACE notify characteristic, so that logic is testable independent of
/// BLEBatteryLink (which can't easily be unit tested — it owns real CoreBluetooth objects).
///
/// The RACE notify characteristic requires an encrypted BLE link. On a Mac that hasn't paired/
/// bonded with the headphones yet, CoreBluetooth reports that back on
/// didUpdateNotificationStateFor as CBATTError.insufficientEncryption/.insufficientAuthentication
/// — not necessarily a one-shot failure, since macOS may still be mid-pairing-prompt, so a few
/// retries a few seconds apart give the user a chance to accept it. This never retries forever:
/// at most `maxRetries` times, and never while disconnected.
@MainActor
final class RaceSubscriptionCoordinator {
    static let maxRetries = 4

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "RaceSubscriptionCoordinator")
    private weak var subscriber: RaceNotifySubscribing?
    private let scheduleRetry: (@escaping () -> Void) -> Void

    private(set) var status: RaceLinkStatus = .notConnected
    private(set) var retryCount = 0
    private(set) var isSubscribed = false
    private(set) var lastErrorDomain: String?
    private(set) var lastErrorCode: Int?
    private(set) var lastErrorText: String?

    private var isConnected = false
    private var hasWriteCharacteristic = false
    /// Bumped on connect, disconnect, success, and every new retry scheduled — a retry's deferred
    /// closure only acts if its captured generation still matches, so a disconnect (or a
    /// reconnect, or a success) reliably cancels whatever was pending instead of a stale timer
    /// firing late and calling back into a subscriber that's no longer in the right state.
    private var retryGeneration = 0

    /// Fires whenever `status` actually changes.
    var onStatusChange: ((RaceLinkStatus) -> Void)?

    init(
        subscriber: RaceNotifySubscribing,
        scheduleRetry: @escaping (@escaping () -> Void) -> Void = { callback in
            DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: callback)
        }
    ) {
        self.subscriber = subscriber
        self.scheduleRetry = scheduleRetry
    }

    /// Call when the peripheral connects. Resets retry/error state for the new connection.
    func handleConnect() {
        isConnected = true
        isSubscribed = false
        hasWriteCharacteristic = false
        retryCount = 0
        retryGeneration += 1
        clearError()
        updateStatus()
    }

    /// Call when the peripheral disconnects (or monitoring stops). Cancels any pending retry —
    /// never leaves one scheduled against a connection that's gone.
    func handleDisconnect() {
        isConnected = false
        isSubscribed = false
        hasWriteCharacteristic = false
        retryGeneration += 1
        updateStatus()
    }

    /// Call once the write-without-response characteristic is discovered and stored.
    func handleWriteCharacteristicDiscovered() {
        hasWriteCharacteristic = true
        updateStatus()
    }

    /// Call from didUpdateNotificationStateFor with the result of a setNotifyValue(true) attempt
    /// (the initial one or a retry).
    func handleSubscriptionResult(isNotifying: Bool, error: Error?) {
        if isNotifying, error == nil {
            isSubscribed = true
            retryCount = 0
            retryGeneration += 1
            clearError()
            updateStatus()
            return
        }

        isSubscribed = false
        guard let error, Self.isEncryptionRelated(error) else {
            updateStatus()
            return
        }

        recordError(error)
        logger.info(
            "RACE subscription needs an encrypted link (pairing); waiting — \(Self.describe(error), privacy: .public)"
        )
        updateStatus()
        scheduleRetryIfPossible()
    }

    private func scheduleRetryIfPossible() {
        guard isConnected else { return }
        guard retryCount < Self.maxRetries else {
            logger.info("RACE notify subscription retries exhausted after \(self.retryCount, privacy: .public) attempts; still not subscribed")
            return
        }
        let attemptNumber = retryCount + 1
        retryGeneration += 1
        let generation = retryGeneration
        scheduleRetry { [weak self] in
            guard let self, generation == self.retryGeneration, self.isConnected else { return }
            self.retryCount = attemptNumber
            self.logger.info("RACE notify subscription retry attempt \(attemptNumber, privacy: .public)/\(Self.maxRetries, privacy: .public)")
            self.subscriber?.subscribeToRaceNotify()
        }
    }

    private func updateStatus() {
        let newStatus: RaceLinkStatus
        if !isConnected {
            newStatus = .notConnected
        } else if isSubscribed && hasWriteCharacteristic {
            newStatus = .ready
        } else if lastErrorDomain != nil {
            newStatus = .needsPairing
        } else {
            newStatus = .connecting
        }
        guard newStatus != status else { return }
        status = newStatus
        logger.info("RACE link status changed to \(String(describing: newStatus), privacy: .public)")
        onStatusChange?(newStatus)
    }

    private func recordError(_ error: Error) {
        let nsError = error as NSError
        lastErrorDomain = nsError.domain
        lastErrorCode = nsError.code
        lastErrorText = nsError.localizedDescription
    }

    private func clearError() {
        lastErrorDomain = nil
        lastErrorCode = nil
        lastErrorText = nil
    }

    private static func isEncryptionRelated(_ error: Error) -> Bool {
        guard let attError = error as? CBATTError else { return false }
        switch attError.code {
        case .insufficientEncryption, .insufficientAuthentication:
            return true
        default:
            return false
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) text=\(nsError.localizedDescription)"
    }
}
