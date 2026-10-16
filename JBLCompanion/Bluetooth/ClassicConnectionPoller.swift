import Foundation
import os.log

/// Drives the warm-up-delay-then-repeated-poll schedule used to catch a device that was already
/// connected before this process started. Pure timing/state logic, injectable so it's testable
/// without real IOBluetooth — ClassicConnectionMonitor owns the real `isConnected()` query; this
/// only decides *when* to ask.
///
/// Why this exists: IOBluetoothDevice.isConnected() queried synchronously at the earliest possible
/// moment of process launch can return false for a device that actually is connected — the same
/// client-side XPC-session warm-up race documented on RFCOMMRaceLink's first-open delay. There is
/// no notification for "it was already connected when I started listening" (notifications only
/// fire on a *new* connect event), so a single immediate check has no way to recover from a false
/// negative here; a short warm-up plus repeated checks does.
@MainActor
final class ClassicConnectionPoller {
    static let warmUpDelay: TimeInterval = 2
    static let fastPollInterval: TimeInterval = 3
    static let fastPollWindow: TimeInterval = 30
    static let slowPollInterval: TimeInterval = 10

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "ClassicConnectionPoller")
    private let checkIsConnected: () -> Bool
    private let scheduleCheck: (TimeInterval, @escaping () -> Void) -> Void
    private let onConnected: (_ source: String) -> Void

    private var isActive = false
    private var elapsed: TimeInterval = 0
    private var hasCheckedOnce = false
    /// Bumped on every start()/stop(), so a check scheduled before a stop() (or before a fresh
    /// start()) never fires against stale state — the same cancellation pattern used by
    /// RFCOMMOpenRetryCoordinator and the deleted RaceSubscriptionCoordinator.
    private var generation = 0

    init(
        checkIsConnected: @escaping () -> Bool,
        scheduleCheck: @escaping (TimeInterval, @escaping () -> Void) -> Void = { delay, callback in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: callback)
        },
        onConnected: @escaping (_ source: String) -> Void
    ) {
        self.checkIsConnected = checkIsConnected
        self.scheduleCheck = scheduleCheck
        self.onConnected = onConnected
    }

    /// Starts (or restarts) the warm-up-then-poll schedule.
    func start() {
        generation += 1
        isActive = true
        elapsed = 0
        hasCheckedOnce = false
        scheduleNextCheck(after: Self.warmUpDelay)
    }

    /// Stops polling — called once a connection is found some other way too (a real connect
    /// notification arriving while polling is still in progress), so polling never continues
    /// pointlessly after the thing it exists to detect has already been detected.
    func stop() {
        generation += 1
        isActive = false
    }

    private func scheduleNextCheck(after delay: TimeInterval) {
        let thisGeneration = generation
        scheduleCheck(delay) { [weak self] in
            guard let self, thisGeneration == self.generation else { return }
            self.performCheck(afterDelay: delay)
        }
    }

    private func performCheck(afterDelay delay: TimeInterval) {
        guard isActive else { return }
        elapsed += delay
        let source = hasCheckedOnce ? "poll timer" : "initial poll"
        hasCheckedOnce = true

        if checkIsConnected() {
            isActive = false
            logger.info("Classic device found connected via \(source, privacy: .public)")
            onConnected(source)
            return
        }

        let nextInterval = elapsed < Self.fastPollWindow ? Self.fastPollInterval : Self.slowPollInterval
        scheduleNextCheck(after: nextInterval)
    }
}
