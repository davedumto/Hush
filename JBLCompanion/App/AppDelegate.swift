import AppKit
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "AppDelegate")

    let headphoneState = HeadphoneState()
    private let profile: DeviceProfile = Tune770NCProfile()
    private lazy var writeGuard = WriteGuard(allowlist: profile.writeAllowlist)
    private lazy var classicMonitor = ClassicConnectionMonitor(classicAddress: profile.classicAddress)
    private lazy var bleLink = BLEBatteryLink(profile: profile)
    private lazy var noiseControlCommander = NoiseControlCommander(profile: profile, writeGuard: writeGuard, transport: bleLink)
    private lazy var noiseModeCoordinator = NoiseModeRequestCoordinator(state: headphoneState, sender: noiseControlCommander)
    private var panel: NotchPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit test target hosts this app (required for @testable import to resolve symbols
        // from an application-type target). Skip real Bluetooth/UI startup in that case so tests
        // don't launch IOBluetooth/CoreBluetooth and risk a blocking permission prompt.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            logger.info("Launched as XCTest host; skipping Bluetooth/UI startup")
            return
        }

        classicMonitor.delegate = self
        bleLink.delegate = self

        let panel = NotchPanel(headphoneState: headphoneState, onSelectNoiseMode: { [weak self] mode in
            self?.requestNoiseMode(mode)
        })
        self.panel = panel
        let showCircle = UserDefaults.standard.object(forKey: "showNotchCircle") as? Bool ?? true
        panel.setVisible(showCircle)

        classicMonitor.start()
        logger.info("JBLCompanion launched; monitoring classic address \(self.profile.classicAddress, privacy: .public)")
    }

    func setNotchVisible(_ visible: Bool) {
        panel?.setVisible(visible)
    }

    /// Call after any IslandSettings change (size, silhouette, fits, outline, display) so the
    /// panel re-resolves its geometry and re-presents at the current size.
    ///
    /// Deferred to the next run loop turn on purpose: this fires from inside a SwiftUI control's
    /// own onChange (a Stepper's +/- tap, a Toggle, a Picker selection) while the Island settings
    /// popover is open. settingsDidChange() synchronously resizes/repositions NotchPanel — a
    /// different window — and doing that synchronously, inside the same event that's still being
    /// handled by the popover's own control, is exactly the kind of thing that can make an
    /// unrelated window's frame change read as "focus moved away" and dismiss a transient
    /// .window-style MenuBarExtra popover. Letting the click finish first avoids that.
    func notchSettingsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.settingsDidChange()
        }
    }

    var isCurrentDisplayNotched: Bool {
        panel?.isNotched ?? false
    }

    func requestNoiseMode(_ mode: CommandableNoiseMode) {
        noiseModeCoordinator.requestMode(mode)
    }
}

extension AppDelegate: ClassicConnectionMonitorDelegate {
    func classicConnectionMonitorDidConnect(_ monitor: ClassicConnectionMonitor) {
        headphoneState.connection = .connected
        headphoneState.deviceName = profile.displayName
        headphoneState.lastUpdated = Date()
        bleLink.startMonitoring()
        panel?.handleClassicConnected()
    }

    func classicConnectionMonitorDidDisconnect(_ monitor: ClassicConnectionMonitor) {
        headphoneState.connection = .disconnected
        headphoneState.batteryPercent = nil
        headphoneState.deviceName = ""
        headphoneState.pendingNoiseMode = nil
        headphoneState.noiseModeConfirmationTimedOut = false
        headphoneState.noiseMode = .unknown
        bleLink.stopMonitoring()
        panel?.handleClassicDisconnected()
    }
}

extension AppDelegate: BLEBatteryLinkDelegate {
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateBatteryPercent percent: Int) {
        headphoneState.batteryPercent = percent
        headphoneState.lastUpdated = Date()
    }

    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateNoiseMode mode: NoiseMode) {
        noiseModeCoordinator.handleConfirmation(mode)
    }

    func bleBatteryLinkDidDisconnect(_ link: BLEBatteryLink) {
        headphoneState.batteryPercent = nil
        headphoneState.pendingNoiseMode = nil
        headphoneState.noiseModeConfirmationTimedOut = false
        headphoneState.noiseMode = .unknown
    }
}
