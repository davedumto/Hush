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
    private lazy var rfcommLink = RFCOMMRaceLink(profile: profile)
    private lazy var noiseControlCommander = NoiseControlCommander(writeGuard: writeGuard, transport: rfcommLink)
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
        rfcommLink.delegate = self

        let panel = NotchPanel(
            headphoneState: headphoneState,
            onSelectNoiseMode: { [weak self] mode in self?.requestNoiseMode(mode) },
            isModeVerified: { [weak self] mode in self?.isModeVerified(mode) ?? false }
        )
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
    /// Deferred to the next run loop turn: this fires from inside a SwiftUI control's own
    /// onChange (a Stepper's +/- tap, a Toggle, a Picker selection) in the Island Settings window,
    /// while that control's own click is still being handled. Letting the click finish first
    /// avoids resizing/repositioning a different window (NotchPanel) synchronously, mid-gesture.
    func notchSettingsDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.settingsDidChange()
        }
    }

    var isCurrentDisplayNotched: Bool {
        panel?.isNotched ?? false
    }

    /// Whether `mode`'s command frame is independently verified — the segmented control and the
    /// menu bar dropdown both gate on this, not just on link readiness, since an unverified
    /// command frame could be sending something other than what it's labeled.
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool {
        profile.isModeVerified(mode)
    }

    func requestNoiseMode(_ mode: CommandableNoiseMode) {
        noiseModeCoordinator.requestMode(mode)
    }

    #if DEBUG
    /// Every mode currently verified — exactly what "Send test frame…" offers, so the Debug menu
    /// never exposes a way to test (or accidentally send) an unverified command.
    var debugTestableModes: [CommandableNoiseMode] {
        CommandableNoiseMode.allCases.filter { profile.isModeVerified($0) }
    }

    /// Sends `mode` through the exact same path as a normal tap (still behind WriteGuard, the
    /// rate limit, and the confirmation timeout) and starts collecting the next 5 RACE events so
    /// they can be read back without editing/rebuilding to add temporary logging.
    func sendDebugTestFrame(_ mode: CommandableNoiseMode) {
        headphoneState.debugRecentEvents = []
        requestNoiseMode(mode)
    }
    #endif

    /// Plain-text snapshot of the noise-control link's state, for the "Copy Diagnostics" menu
    /// item. Read-only — only reads already-tracked state, never touches the headphones.
    func diagnosticsText() -> String {
        return """
        JBLCompanion diagnostics
        Classic connection: \(classicMonitor.isConnectedDescription)
        HeadphoneState.connection: \(headphoneState.connection)
        RFCOMM state: \(rfcommLink.channelStateDescription)
        Last RFCOMM open IOReturn: \(rfcommLink.lastOpenIOReturn ?? "never attempted")
        RFCOMM open retry count: \(rfcommLink.openRetryCount)
        Last frames received: \(rfcommLink.recentFrameDescriptions.isEmpty ? "none" : rfcommLink.recentFrameDescriptions.joined(separator: " | "))
        Reassembler stats: \(rfcommLink.reassemblerStatsDescription)
        Noise mode: \(headphoneState.noiseMode.displayText)
        Pending noise mode: \(headphoneState.pendingNoiseMode?.displayText ?? "none")
        """
    }
}

extension AppDelegate: ClassicConnectionMonitorDelegate {
    func classicConnectionMonitorDidConnect(_ monitor: ClassicConnectionMonitor) {
        headphoneState.connection = .connected
        headphoneState.deviceName = profile.displayName
        headphoneState.lastUpdated = Date()
        bleLink.startMonitoring()
        rfcommLink.handleClassicConnected()
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
        rfcommLink.handleClassicDisconnected()
        panel?.handleClassicDisconnected()
    }
}

extension AppDelegate: BLEBatteryLinkDelegate {
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateBatteryPercent percent: Int) {
        headphoneState.batteryPercent = percent
        headphoneState.lastUpdated = Date()
    }

    func bleBatteryLinkDidDisconnect(_ link: BLEBatteryLink) {
        headphoneState.batteryPercent = nil
    }
}

extension AppDelegate: RFCOMMRaceLinkDelegate {
    func rfcommRaceLink(_ link: RFCOMMRaceLink, didUpdateNoiseMode mode: NoiseMode) {
        noiseModeCoordinator.handleConfirmation(mode)
        #if DEBUG
        if headphoneState.debugRecentEvents.count < 5 {
            headphoneState.debugRecentEvents.append("\(Date().formatted(date: .omitted, time: .standard)): \(mode.displayText)")
        }
        #endif
    }
}
