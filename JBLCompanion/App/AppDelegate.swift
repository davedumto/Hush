import AppKit
import Observation
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
    /// Checkmark state refreshed in menuWillOpen(_:) — stored rather than looked up by title
    /// (NSMenu.item(withTitle:)), which would silently break again the next time this item's
    /// title text changes.
    private var showHushMenuItem: NSMenuItem?
    #if DEBUG
    /// Its submenu is rebuilt fresh in menuWillOpen(_:) each time the fallback menu opens, from
    /// debugTestableModes — the item itself is created once and just hidden when there's nothing
    /// to test, rather than inserting/removing it from the main menu's own item list.
    private var debugMenuItem: NSMenuItem?
    #endif

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
        // NSStatusItem is about as close to guaranteed-to-work as menu bar UI gets. This is now
        // the app's only menu bar item (JBLCompanionApp no longer declares its own MenuBarExtra —
        // two status items for one app was the actual bug "fallback" implied fixing).
        setupFallbackStatusItem()
        startObservingHeadphoneStateForMenuBarIcon()

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
        fallbackStatusItem = item
        updateMenuBarIcon() // reflects the real (disconnected) state immediately, not the SF Symbol placeholder it replaces.

        let menu = NSMenu()
        menu.delegate = self

        let islandSettingsItem = NSMenuItem(title: "Island Settings…", action: #selector(openIslandSettingsFromFallback), keyEquivalent: "")
        islandSettingsItem.target = self
        menu.addItem(islandSettingsItem)

        menu.addItem(.separator())

        let showHushItem = NSMenuItem(title: "Show Hush", action: #selector(toggleShowHushFromFallback), keyEquivalent: "")
        showHushItem.target = self
        menu.addItem(showHushItem)
        showHushMenuItem = showHushItem

        let resetPositionItem = NSMenuItem(title: "Reset Position & Display", action: #selector(resetPositionFromFallback), keyEquivalent: "")
        resetPositionItem.target = self
        menu.addItem(resetPositionItem)

        menu.addItem(.separator())

        let copyDiagnosticsItem = NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnosticsFromFallback), keyEquivalent: "")
        copyDiagnosticsItem.target = self
        menu.addItem(copyDiagnosticsItem)

        #if DEBUG
        // Created once, hidden/shown and its submenu rebuilt in menuWillOpen(_:) — never
        // inserted/removed from the main menu's own item list (see `debugMenuItem`'s own doc
        // comment).
        menu.addItem(.separator())
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugItem.submenu = NSMenu()
        menu.addItem(debugItem)
        debugMenuItem = debugItem
        #endif

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromFallback), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        logger.info("Fallback NSStatusItem created")
    }

    // MARK: - Menu bar icon by mode (design/DESIGN_GUIDE.md §7)

    /// Reflects `headphoneState` right now — called once at setup and again on every change (see
    /// `startObservingHeadphoneStateForMenuBarIcon`). MenuBarIconResolver reads only the confirmed
    /// `noiseMode`, never `pendingNoiseMode` — CLAUDE.md: "A mode is shown as active only after a
    /// 5C status event."
    private func updateMenuBarIcon() {
        let assetName = MenuBarIconResolver.assetName(connection: headphoneState.connection, confirmedMode: headphoneState.noiseMode)
        let image = NSImage(named: assetName)
        // Explicit, not left to the asset catalog's own "Render As: Template" setting (which is
        // already on for all four MenuBar* assets) — macOS only tints a template image for light
        // and dark menu bars when this is true, and setting it here keeps that guarantee visible
        // in code rather than silently trusting catalog metadata.
        image?.isTemplate = true
        fallbackStatusItem?.button?.image = image
    }

    /// HeadphoneState is @Observable, but AppDelegate is plain AppKit, not a SwiftUI view, so
    /// nothing re-renders it automatically. `withObservationTracking` is the general-purpose
    /// Observation API for exactly this: the first closure's reads register the dependency, and
    /// `onChange` fires once when any of them change — re-arming itself each time is what keeps
    /// this running for the app's whole lifetime rather than firing only once. This reacts
    /// correctly to every mutation site (AppDelegate's own connect/disconnect handling *and*
    /// NoiseModeRequestCoordinator's confirmed-mode updates) without needing a manual update call
    /// at each one — the coordinator is Bluetooth-layer code this task doesn't touch.
    private func startObservingHeadphoneStateForMenuBarIcon() {
        withObservationTracking {
            _ = headphoneState.connection
            _ = headphoneState.noiseMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateMenuBarIcon()
                self?.startObservingHeadphoneStateForMenuBarIcon() // re-arms itself — see this method's own doc comment.
            }
        }
    }

    @objc private func openIslandSettingsFromFallback() {
        panel?.requestOpenIslandSettings()
    }

    @objc private func toggleShowHushFromFallback() {
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

    var currentDockEdge: DockEdge {
        panel?.currentEdge ?? .top
    }

    /// Island Settings' edge picker. Same next-run-loop-turn deferral as `notchSettingsDidChange`
    /// and for the same reason — this fires from inside the Picker's own onChange while it's
    /// still mid-click.
    func setDockEdge(_ edge: DockEdge) {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.setDockEdge(edge)
        }
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
        var base: String
        if let session = activeSession {
            base = """
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
        } else {
            base = """
            JBLCompanion diagnostics
            Matched profile: none
            Classic connection: \(classicMonitor.isConnectedDescription)
            HeadphoneState.connection: \(headphoneState.connection)
            """
        }
        #if DEBUG
        // "Send test frame…" has no dropdown of its own to show the events it collects now that
        // the fallback menu is the app's only one — folded into Copy Diagnostics instead, the
        // other surface this task asks to keep working, rather than losing that feedback entirely.
        let recent = headphoneState.debugRecentEvents.isEmpty ? "none" : headphoneState.debugRecentEvents.joined(separator: " | ")
        base += "\nRecent test-frame events: \(recent)"
        #endif
        return base
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
    /// Refreshes the fallback menu's "Show Hush" checkmark, and (DEBUG only) rebuilds the "Debug"
    /// submenu's "Send test frame…" items from whichever modes the currently active profile has
    /// verified, right before the menu opens — simpler than trying to keep either in sync after
    /// every change elsewhere (a profile match, a toggle from some other surface).
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === fallbackStatusItem?.menu else { return }
        let showing = UserDefaults.standard.object(forKey: "showNotchCircle") as? Bool ?? true
        showHushMenuItem?.state = showing ? .on : .off
        #if DEBUG
        rebuildDebugTestFrameSubmenu()
        #endif
    }

    #if DEBUG
    /// `debugMenuItem` and its submenu are created once in setupFallbackStatusItem() and never
    /// touch the main menu's own item list again — only hidden when there's nothing to test, and
    /// its submenu's contents replaced, so switching profiles (or losing the connection entirely)
    /// never leaves a stale mode's item behind.
    private func rebuildDebugTestFrameSubmenu() {
        guard let submenu = debugMenuItem?.submenu else { return }
        debugMenuItem?.isHidden = debugTestableModes.isEmpty
        submenu.removeAllItems()
        for mode in debugTestableModes {
            let item = NSMenuItem(
                title: "Send test frame: \(mode.displayText)", action: #selector(sendDebugTestFrameFromFallback(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            item.isEnabled = headphoneState.pendingNoiseMode == nil
            submenu.addItem(item)
        }
    }

    @objc private func sendDebugTestFrameFromFallback(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? CommandableNoiseMode else { return }
        sendDebugTestFrame(mode)
    }
    #endif
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
