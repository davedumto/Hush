import Foundation
import UserNotifications

/// Posts the actual system notification — a protocol (not a bare `UNUserNotificationCenter` call at
/// the use site) so `LowBatteryAlertCoordinatorTests` can verify the crossing/debounce logic without
/// ever touching the real notification center or requiring the test process to be a signed `.app`
/// bundle at all.
protocol LowBatteryNotifying {
    func requestAuthorizationIfNeeded()
    func postLowBatteryAlert(deviceName: String, batteryPercent: Int)
}

/// Researched, not guessed: `UNUserNotificationCenter` (not the deprecated `NSUserNotificationCenter`)
/// is the correct, current API, and ad-hoc signing (Hush's own `CODE_SIGN_IDENTITY: "-"`, project.yml)
/// is confirmed sufficient — no paid Developer ID needed, only a signed bundle with a real bundle
/// identifier, which this app already has. `LSUIElement`/accessory status doesn't block delivery
/// either; the one real gotcha confirmed by research is that a menu-bar app is effectively always
/// "foreground," so without implementing `userNotificationCenter(_:willPresent:withCompletionHandler:)`
/// and explicitly returning `.banner`, macOS silently suppresses the notification by default.
final class UNUserNotificationLowBatteryNotifier: NSObject, LowBatteryNotifying, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() {
        // Idempotent in practice (macOS remembers the grant/denial after the first prompt), but
        // idiomatic to call on every launch anyway — a no-op once decided, and lets the app react
        // if the user later revokes permission in System Settings rather than silently failing.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postLowBatteryAlert(deviceName: String, batteryPercent: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(deviceName) Battery Low"
        content.body = "\(batteryPercent)% remaining — time to charge soon."
        content.sound = .default
        // `trigger: nil` delivers immediately, not on a schedule — this fires the moment the
        // coordinator below decides to alert, not at some later time.
        let request = UNNotificationRequest(identifier: "com.davidejere.Hush.lowBattery", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Owner spec, 2026-11-07, feature brainstorm #1: "low battery alert — a notification when
/// headphones drop below a threshold (e.g. 15%), so you're not caught off guard." Reuses
/// `PillVariant.lowBatteryThreshold` (15) — the same threshold the low-battery pill/chip UI already
/// uses — rather than a second, separately-tunable number that could silently drift out of sync
/// with what the UI itself calls "low."
///
/// Fires at most once per "low period": the moment a reading first crosses below the threshold, not
/// on every subsequent reading while still low (confirmed against how iOS's own system battery
/// alert behaves — research, not guessed). The alerted flag resets once the battery recovers to
/// at/above the threshold or the headphones disconnect (`batteryPercent == nil`), so a later low dip
/// alerts again.
final class LowBatteryAlertCoordinator {
    private let notifier: LowBatteryNotifying
    private var hasAlertedForCurrentLowPeriod = false

    init(notifier: LowBatteryNotifying = UNUserNotificationLowBatteryNotifier()) {
        self.notifier = notifier
    }

    func start() {
        notifier.requestAuthorizationIfNeeded()
    }

    /// Called on every trusted battery reading (AppDelegate's own `BLEBatteryLinkDelegate`
    /// conformance skips this for an unverified-zero reading — `BatteryReadingPolicy`'s own doc
    /// comment on why that 0% isn't trustworthy enough to act on, alert or otherwise).
    func update(batteryPercent: Int?, deviceName: String) {
        let isLow = batteryPercent.map { $0 < PillVariant.lowBatteryThreshold } ?? false
        guard isLow else {
            hasAlertedForCurrentLowPeriod = false
            return
        }
        guard !hasAlertedForCurrentLowPeriod, let batteryPercent else { return }
        hasAlertedForCurrentLowPeriod = true
        notifier.postLowBatteryAlert(
            deviceName: deviceName.isEmpty ? "Your headphones" : deviceName, batteryPercent: batteryPercent
        )
    }
}
