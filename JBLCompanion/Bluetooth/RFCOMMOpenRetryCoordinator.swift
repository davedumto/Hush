import Foundation
import os.log

/// Owns the "a failed RFCOMM open gets retried a few times, a few seconds apart, then gives up"
/// schedule. Pure timing/state logic, injectable so it's testable without real IOBluetooth —
/// RFCOMMRaceLink owns the real open attempt and its IOReturn; this only decides *whether and
/// when* to try again.
@MainActor
final class RFCOMMOpenRetryCoordinator {
    static let maxRetries = 3
    static let retryInterval: TimeInterval = 3

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "RFCOMMOpenRetryCoordinator")
    private let scheduleRetry: (@escaping () -> Void) -> Void
    private let attemptOpen: () -> Void

    private(set) var retryCount = 0
    /// Bumped on start()/cancel()/handleOpenSuccess() — the same cancellation pattern as the
    /// deleted RaceSubscriptionCoordinator, so a retry scheduled before a disconnect (or before a
    /// fresh start()) never fires against stale state.
    private var generation = 0

    init(
        scheduleRetry: @escaping (@escaping () -> Void) -> Void = { callback in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: callback)
        },
        attemptOpen: @escaping () -> Void
    ) {
        self.scheduleRetry = scheduleRetry
        self.attemptOpen = attemptOpen
    }

    /// Call when a fresh connection attempt should begin (classic just connected, or the channel
    /// just closed while still classic-connected). Resets the retry count and makes the first
    /// attempt immediately.
    func start() {
        generation += 1
        retryCount = 0
        attemptOpen()
    }

    /// Call on disconnect — cancels any pending retry. A later start() begins fresh.
    func cancel() {
        generation += 1
    }

    /// Call when the open attempt just made (from start() or a previous retry) failed. Schedules
    /// another attempt unless the retry cap has been reached. Never retries forever.
    func handleOpenFailure() {
        guard retryCount < Self.maxRetries else {
            logger.info("RFCOMM open retries exhausted after \(self.retryCount, privacy: .public) attempts")
            return
        }
        let attemptNumber = retryCount + 1
        generation += 1
        let thisGeneration = generation
        scheduleRetry { [weak self] in
            guard let self, thisGeneration == self.generation else { return }
            self.retryCount = attemptNumber
            self.logger.info("RFCOMM open retry attempt \(attemptNumber, privacy: .public)/\(Self.maxRetries, privacy: .public)")
            self.attemptOpen()
        }
    }

    /// Call when an open attempt succeeds — resets the count for next time.
    func handleOpenSuccess() {
        generation += 1
        retryCount = 0
    }
}
