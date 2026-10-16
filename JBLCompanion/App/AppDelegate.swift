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

        let panel = NotchPanel(headphoneState: headphoneState)
        self.panel = panel
        let showCircle = UserDefaults.standard.object(forKey: "showNotchCircle") as? Bool ?? true
        panel.setVisible(showCircle)

        classicMonitor.start()
        logger.info("JBLCompanion launched; monitoring classic address \(self.profile.classicAddress, privacy: .public)")
    }

    func setNotchVisible(_ visible: Bool) {
        panel?.setVisible(visible)
    }

    func repositionNotch() {
        panel?.reposition()
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
        headphoneState.noiseMode = mode
        headphoneState.lastUpdated = Date()
    }

    func bleBatteryLinkDidDisconnect(_ link: BLEBatteryLink) {
        headphoneState.batteryPercent = nil
        headphoneState.noiseMode = .unknown
    }
}
