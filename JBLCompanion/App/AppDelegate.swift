import AppKit
import os.log

/// Bundles the per-connection objects (write guard, BLE battery link, RFCOMM RACE link, noise
/// control commander/coordinator) for whichever DeviceProfile actually matched the device that
/// just connected. AppDelegate no longer builds these once against one hardcoded profile at
/// launch — see ClassicConnectionMonitor/DeviceProfileMatcher for why a profile is now chosen
/// dynamically, from the real connected device's name.
@MainActor
private final class ActiveDeviceSession {
    let profile: DeviceProfile
    let connectedAddress: String
    let addressConfirmed: Bool
    let writeGuard: WriteGuard
    let bleLink: BLEBatteryLink
    let rfcommLink: RFCOMMRaceLink
    let noiseControlCommander: NoiseControlCommander
    let noiseModeCoordinator: NoiseModeRequestCoordinator

    init(profile: DeviceProfile, connectedAddress: String, addressConfirmed: Bool, state: HeadphoneState) {
        self.profile = profile
        self.connectedAddress = connectedAddress
        self.addressConfirmed = addressConfirmed
        let writeGuard = WriteGuard(allowlist: profile.writeAllowlist)
        let rfcommLink = RFCOMMRaceLink(profile: profile, classicAddress: connectedAddress)
        let noiseControlCommander = NoiseControlCommander(writeGuard: writeGuard, transport: rfcommLink)
        self.writeGuard = writeGuard
        self.bleLink = BLEBatteryLink(profile: profile)
        self.rfcommLink = rfcommLink
        self.noiseControlCommander = noiseControlCommander
        self.noiseModeCoordinator = NoiseModeRequestCoordinator(state: state, sender: noiseControlCommander)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "AppDelegate")

    let headphoneState = HeadphoneState()
    private let profiles: [DeviceProfile] = [Tune770NCProfile(), Tune670NCProfile()]
    private lazy var classicMonitor = ClassicConnectionMonitor(profiles: profiles)
    private var activeSession: ActiveDeviceSession?
    private var panel: NotchPanel?
    private var fallbackStatusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit test target hosts this app (required for @testable import to resolve symbols
        // from an application-type target). Skip real Bluetooth/UI startup in that case so tests
        // don't launch IOBluetooth/CoreBluetooth and risk a blocking permission prompt.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            logger.info("Launched as XCTest host; skipping Bluetooth/UI startup")
            return
        }

        #if DEBUG
        if PreviewSnapshotHarness.runIfRequested() {
            NSApplication.shared.terminate(nil)
            return
        }
        #endif

        verifyRequiredFonts()

        // Created first, before anything else in this method that could fail — a plain AppKit
        // NSStatusItem is about as close to guaranteed-to-work as menu bar UI gets, unlike
        // SwiftUI's MenuBarExtra (JBLCompanionApp), so this exists specifically so the app is
        // never completely inaccessible even if something downstream silently fails to show.
        setupFallbackStatusItem()

        classicMonitor.delegate = self

        let panel = NotchPanel(
            headphoneState: headphoneState,
            onSelectNoiseMode: { [weak self] mode in self?.requestNoiseMode(mode) },
            isModeVerified: { [weak self] mode in self?.isModeVerified(mode) ?? false },
            supportsNoiseControl: { [weak self] in self?.activeSession?.profile.supportsNoiseControl ?? false },
            onReconnectTapped: { [weak self] in self?.reconnect() },
            onOpenBluetoothSettingsTapped: { [weak self] in self?.openBluetoothSettings() },
            lastMatchedProfileDisplayName: { Self.lastMatchedProfileDisplayName }
        )
        self.panel = panel
        let showCircle = UserDefaults.standard.object(forKey: "showNotchCircle") as? Bool ?? true
        panel.setVisible(showCircle)

        classicMonitor.start()
        logger.info("JBLCompanion launched; watching for: \(self.profiles.map(\.displayName).joined(separator: ", "), privacy: .public)")
    }

    /// RequiredFonts.postScriptNames (design/DESIGN_GUIDE.md §2) should already be registered via
    /// ATSApplicationFontsPath (project.yml) by the time this runs — this only verifies that
    /// actually happened and logs a warning per name that didn't resolve, rather than silently
    /// falling back to the system font everywhere Theme.Fonts is used.
    private func verifyRequiredFonts() {
        let unresolved = RequiredFonts.unresolved(resolves: { NSFont(name: $0, size: 12) != nil })
        for name in unresolved {
            logger.warning("Required font did not resolve at runtime: \(name, privacy: .public)")
        }
    }

    // MARK: - AppKit status-item fallback (always present — see applicationDidFinishLaunching)

    private func setupFallbackStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "JBL Companion")

        let menu = NSMenu()
        menu.delegate = self

        let showNotchItem = NSMenuItem(title: "Show Notch", action: #selector(toggleShowNotchFromFallback), keyEquivalent: "")
        showNotchItem.target = self
        menu.addItem(showNotchItem)

        let resetPositionItem = NSMenuItem(title: "Reset Position", action: #selector(resetPositionFromFallback), keyEquivalent: "")
        resetPositionItem.target = self
        menu.addItem(resetPositionItem)

        menu.addItem(.separator())

        let copyDiagnosticsItem = NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnosticsFromFallback), keyEquivalent: "")
        copyDiagnosticsItem.target = self
        menu.addItem(copyDiagnosticsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromFallback), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        fallbackStatusItem = item
        logger.info("Fallback NSStatusItem created")
    }

    @objc private func toggleShowNotchFromFallback() {
        let current = UserDefaults.standard.object(forKey: "showNotchCircle") as? Bool ?? true
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: "showNotchCircle")
        setNotchVisible(newValue)
    }

    @objc private func resetPositionFromFallback() {
        panel?.resetToDefaultDisplay()
    }

    @objc private func copyDiagnosticsFromFallback() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsText(), forType: .string)
    }

    @objc private func quitFromFallback() {
        NSApplication.shared.terminate(nil)
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
    /// command frame could be sending something other than what it's labeled. False whenever no
    /// profile is actively connected.
    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool {
        activeSession?.profile.isModeVerified(mode) ?? false
    }

    func requestNoiseMode(_ mode: CommandableNoiseMode) {
        activeSession?.noiseModeCoordinator.requestMode(mode)
    }

    // MARK: - §5 "No headphones" actions

    private static let lastMatchedProfileDisplayNameKey = "lastMatchedProfileDisplayName"

    /// design/DESIGN_GUIDE.md §5: "Last seen: <last matched profile display name>" — written once
    /// per successful classic-connect match (below), read back by ExpandedCard's no-device layout.
    /// A static UserDefaults accessor, not instance state, so NotchPanel's view-layer closure can
    /// read it without holding a reference to AppDelegate.
    static var lastMatchedProfileDisplayName: String? {
        UserDefaults.standard.string(forKey: lastMatchedProfileDisplayNameKey)
    }

    /// Re-runs classic detection through the exact same entry points `applicationDidFinishLaunching`
    /// itself uses — `stop()` first, not just `start()` again, so a repeated tap never leaks a
    /// second notification registration/poller on top of the one from launch (ClassicConnectionMonitor
    /// isn't written to be called twice without an intervening `stop()`). If the device is still
    /// classically connected, this chains straight back through `classicConnectionMonitor(_:didConnect:...)`
    /// exactly as a fresh connect would, which is what re-opens RFCOMM — no RFCOMM-specific code
    /// here at all, and ClassicConnectionMonitor/RFCOMMRaceLink are untouched.
    func reconnect() {
        logger.info("Reconnect requested from the no-headphones card")
        classicMonitor.stop()
        classicMonitor.start()
    }

    /// Plain AppKit, not Bluetooth — opens System Settings' Bluetooth pane.
    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.bluetooth") else { return }
        NSWorkspace.shared.open(url)
    }

    #if DEBUG
    /// Every mode currently verified — exactly what "Send test frame…" offers, so the Debug menu
    /// never exposes a way to test (or accidentally send) an unverified command.
    var debugTestableModes: [CommandableNoiseMode] {
        guard let profile = activeSession?.profile else { return [] }
        return CommandableNoiseMode.allCases.filter { profile.isModeVerified($0) }
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
        guard let session = activeSession else {
            return """
            JBLCompanion diagnostics
            Matched profile: none
            Classic connection: \(classicMonitor.isConnectedDescription)
            HeadphoneState.connection: \(headphoneState.connection)
            """
        }
        return """
        JBLCompanion diagnostics
        Matched profile: \(session.profile.displayName) (classicNameMatch=\(session.profile.classicNameMatch), addressConfirmed=\(session.addressConfirmed))
        Connected address: \(session.connectedAddress)
        Classic connection: \(classicMonitor.isConnectedDescription)
        HeadphoneState.connection: \(headphoneState.connection)
        RFCOMM state: \(session.rfcommLink.channelStateDescription)
        Last RFCOMM open IOReturn: \(session.rfcommLink.lastOpenIOReturn ?? "never attempted")
        RFCOMM open retry count: \(session.rfcommLink.openRetryCount)
        Last frames received: \(session.rfcommLink.recentFrameDescriptions.isEmpty ? "none" : session.rfcommLink.recentFrameDescriptions.joined(separator: " | "))
        Reassembler stats: \(session.rfcommLink.reassemblerStatsDescription)
        Event map verified: \(session.profile.eventMapVerified)
        Noise mode: \(headphoneState.noiseMode.displayText)
        Pending noise mode: \(headphoneState.pendingNoiseMode?.displayText ?? "none")
        """
    }
}

extension AppDelegate: ClassicConnectionMonitorDelegate {
    func classicConnectionMonitor(
        _ monitor: ClassicConnectionMonitor, didConnect profile: DeviceProfile,
        address: String, addressConfirmed: Bool
    ) {
        logger.info(
            "Classic connect: matched profile=\(profile.displayName, privacy: .public) because classicNameMatch=\(profile.classicNameMatch, privacy: .public) addressConfirmed=\(addressConfirmed, privacy: .public)"
        )

        // ClassicConnectionMonitor only calls this again for a genuinely different device
        // (shouldSwitch), so a previous session here means a second, different headset just
        // connected — most recently connected wins: the old session is fully torn down (BLE
        // stopped, RFCOMM closed) before the new one takes over, so nothing is ever sent to it
        // again and its events can no longer be misattributed to the new profile.
        if let previous = activeSession {
            logger.info(
                "Switching active device: \(previous.profile.displayName, privacy: .public) -> \(profile.displayName, privacy: .public) (most recently connected wins)"
            )
            previous.bleLink.stopMonitoring()
            previous.rfcommLink.handleClassicDisconnected()
        }

        let session = ActiveDeviceSession(profile: profile, connectedAddress: address, addressConfirmed: addressConfirmed, state: headphoneState)
        activeSession = session
        session.bleLink.delegate = self
        session.rfcommLink.delegate = self

        headphoneState.connection = .connected
        headphoneState.deviceName = profile.displayName
        headphoneState.photoAssetNames = profile.photoAssetNames
        headphoneState.modelNumberText = profile.modelNumberText
        headphoneState.noiseModeEventMapVerified = profile.eventMapVerified
        headphoneState.lastUpdated = Date()
        // design/DESIGN_GUIDE.md §5 "No headphones": persisted so a later disconnect can still
        // show "Last seen: <name>" — survives app relaunch, unlike HeadphoneState itself.
        UserDefaults.standard.set(profile.displayName, forKey: Self.lastMatchedProfileDisplayNameKey)

        session.bleLink.startMonitoring()
        // RFCOMM is now opened for any matched profile, to listen for status — whether writes
        // are ever attempted through it is RFCOMMRaceLink.allowsWrites's job (from
        // DeviceProfile.allowsRFCOMMWrites), not a reason to withhold opening it at all.
        session.rfcommLink.handleClassicConnected()
        panel?.handleClassicConnected()
    }

    func classicConnectionMonitorDidDisconnect(_ monitor: ClassicConnectionMonitor) {
        headphoneState.connection = .disconnected
        headphoneState.batteryPercent = nil
        headphoneState.batteryPercentIsUnverifiedZero = false
        headphoneState.deviceName = ""
        headphoneState.photoAssetNames = nil
        headphoneState.modelNumberText = ""
        headphoneState.pendingNoiseMode = nil
        headphoneState.noiseModeConfirmationTimedOut = false
        headphoneState.noiseMode = .unknown
        headphoneState.noiseModeEventMapVerified = true
        activeSession?.bleLink.stopMonitoring()
        activeSession?.rfcommLink.handleClassicDisconnected()
        activeSession = nil
        panel?.handleClassicDisconnected()
    }
}

extension AppDelegate: BLEBatteryLinkDelegate {
    func bleBatteryLink(_ link: BLEBatteryLink, didUpdateBatteryPercent percent: Int) {
        let trustsZero = activeSession?.profile.trustsZeroBatteryReading ?? true
        let result = BatteryReadingPolicy.apply(rawPercent: percent, trustsZeroBatteryReading: trustsZero)
        if result.isUnverifiedZero {
            logger.warning(
                "Treating 0% battery from \(self.activeSession?.profile.displayName ?? "unknown", privacy: .public) as unverified; raw value=\(percent, privacy: .public)"
            )
        }
        headphoneState.batteryPercent = result.displayPercent
        headphoneState.batteryPercentIsUnverifiedZero = result.isUnverifiedZero
        headphoneState.lastUpdated = Date()
    }

    func bleBatteryLinkDidDisconnect(_ link: BLEBatteryLink) {
        headphoneState.batteryPercent = nil
        headphoneState.batteryPercentIsUnverifiedZero = false
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Refreshes the fallback menu's "Show Notch" checkmark right before it opens, rather than
    /// trying to keep it in sync after every toggle — the SwiftUI MenuBarExtra's own Toggle can
    /// also change the same UserDefaults key, and this way both surfaces always agree.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === fallbackStatusItem?.menu else { return }
        let showing = UserDefaults.standard.object(forKey: "showNotchCircle") as? Bool ?? true
        menu.item(withTitle: "Show Notch")?.state = showing ? .on : .off
    }
}

extension AppDelegate: RFCOMMRaceLinkDelegate {
    func rfcommRaceLink(_ link: RFCOMMRaceLink, didUpdateNoiseMode mode: NoiseMode) {
        activeSession?.noiseModeCoordinator.handleConfirmation(mode)
        #if DEBUG
        if headphoneState.debugRecentEvents.count < 5 {
            headphoneState.debugRecentEvents.append("\(Date().formatted(date: .omitted, time: .standard)): \(mode.displayText)")
        }
        #endif
    }
}
