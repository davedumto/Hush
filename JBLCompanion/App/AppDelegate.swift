import AppKit
import Observation
import Sparkle
import SwiftUI
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
    let equalizerCommander: EqualizerCommander

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
        self.equalizerCommander = EqualizerCommander(writeGuard: writeGuard, transport: rfcommLink)
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
    /// Replaces the old native NSMenu — an NSPopover draws its own rounded-rect-with-arrow chrome
    /// pointing at the status item (the look FallbackMenuView's own doc comment references),
    /// which a plain NSMenu can't do. Its content view is rebuilt fresh on every
    /// toggleFallbackPopover() show, not reused, so DEBUG's test-frame list and "Show Hush"'s
    /// checkmark are never stale the way the old menuWillOpen(_:) rebuild had to guard against.
    private var fallbackPopover: NSPopover?
    /// Reads SUFeedURL/SUPublicEDKey straight from Info.plist (project.yml's own properties) —
    /// `startingUpdater: true` begins Sparkle's own background schedule immediately
    /// (SUEnableAutomaticChecks/SUScheduledCheckInterval, also in Info.plist), independent of
    /// whether the user ever opens "Check for Updates…" themselves.
    private lazy var updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    /// Island Settings/FeedbackView are real restorable `Window` scenes (JBLCompanionApp.swift),
    /// so macOS's own window-state restoration reopens whichever one was left open the moment the
    /// process last exited — which happens on *every* Xcode rebuild (Xcode kills the running
    /// process), making a utility window someone had open for testing silently pop back open on
    /// the next launch. There's nothing in this menu bar app worth restoring across launches, so
    /// this opts the whole app out rather than fighting restoration per-window.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }

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

        // Forces the lazy updaterController to actually init here, at launch — otherwise it
        // would stay uninitialized (and Sparkle's background schedule with it) until the first
        // time someone opens the dropdown and its "Check for Updates…" row is first read.
        _ = updaterController

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
            lastMatchedProfileDisplayName: { Self.lastMatchedProfileDisplayName },
            onPowerOff: { [weak self] in self?.requestPowerOff() },
            canPowerOff: { [weak self] in self?.canPowerOff ?? false },
            canUseEqualizer: { [weak self] in self?.canUseEqualizer ?? false },
            onSelectEqualizerPreset: { [weak self] preset in self?.requestEqualizerPreset(preset) },
            onSetEqualizerOn: { [weak self] on in on ? self?.requestEqualizerOn() : self?.requestEqualizerOff() },
            canUseMaxVolumeLimiter: { [weak self] in self?.canUseMaxVolumeLimiter ?? false },
            onSetMaxVolumeLimiter: { [weak self] on in self?.requestSetMaxVolumeLimiter(on) },
            canUseVoicePrompt: { [weak self] in self?.canUseVoicePrompt ?? false },
            onSetVoicePrompt: { [weak self] on in self?.requestSetVoicePrompt(on) },
            onIslandSettingsChanged: { [weak self] in self?.notchSettingsDidChange() }
        )
        self.panel = panel
        let showCircle = UserDefaults.standard.object(forKey: "showNotchCircle") as? Bool ?? true
        panel.setVisible(showCircle)

        classicMonitor.start()
        logger.info("JBLCompanion launched; watching for: \(self.profiles.map(\.displayName).joined(separator: ", "), privacy: .public)")
    }

    /// The app's only SwiftUI Scene is the Island Settings `Window` (JBLCompanionApp.swift) — with
    /// no override here, AppKit's default behavior for an app whose last window just closed is to
    /// terminate it, which quit the whole menu bar app (notch panel included) every time Island
    /// Settings was closed. This is a menu bar/agent app (LSUIElement) with no main window at all;
    /// it should keep running with no windows open, same as it does before Island Settings is ever
    /// opened for the first time.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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

        // Both left and right click show the dropdown — the island itself is what toggles on
        // click (NotchPanel's own tap handler), not the menu bar icon. sendAction(on:) opts into
        // right-click too, since a plain `action` alone only fires on left click.
        item.button?.target = self
        item.button?.action = #selector(toggleFallbackPopover)
        item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])

        // NSPopover's own `.transient` auto-close only fires on an outside click — switching
        // Space (Mission Control, a 3-finger swipe, Ctrl+arrow) or activating a different app
        // triggers neither, so the popover's window (not configured to join every Space, unlike
        // NotchPanel's own window) was staying open and stuck on whichever Space it was opened
        // on: invisible after switching away, still sitting there if you switched back. Closing
        // it explicitly on both makes it behave like every other menu bar dropdown in macOS.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(closeFallbackPopover),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(closeFallbackPopover),
            name: NSApplication.didResignActiveNotification, object: nil
        )
        logger.info("Fallback NSStatusItem created")
    }

    @objc private func closeFallbackPopover() {
        fallbackPopover?.performClose(nil)
    }

    /// Rebuilds FallbackMenuView fresh every time — see `fallbackPopover`'s own doc comment for
    /// why nothing here is cached/reused across shows.
    @objc private func toggleFallbackPopover() {
        if let fallbackPopover, fallbackPopover.isShown {
            fallbackPopover.performClose(nil)
            return
        }
        guard let button = fallbackStatusItem?.button else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        let hostingController = NSHostingController(
            rootView: FallbackMenuView(appDelegate: self, dismiss: { [weak popover] in popover?.performClose(nil) })
        )
        // Without this, NSPopover shows with its own guessed initial size (not FallbackMenuView's
        // real, wider one), computes the arrow's position against that, then resizes once
        // SwiftUI's actual layout reports back — leaving the arrow stranded at the old, narrower
        // position instead of centered on the box it's now attached to (the "arrow on the side"
        // bug). `.preferredContentSize` keeps NSPopover's contentSize synced to SwiftUI's own
        // ideal size continuously, not just once at creation.
        hostingController.sizingOptions = .preferredContentSize
        popover.contentViewController = hostingController
        fallbackPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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

    /// Called by FallbackMenuView — the fallback popover's own "Island Settings…" row.
    func openIslandSettings() {
        panel?.requestOpenIslandSettings()
    }

    /// Called by FallbackMenuView's "Copy Diagnostics" row.
    func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsText(), forType: .string)
    }

    /// Opens the in-app feedback form (FeedbackView), which posts to the hush-feedback backend —
    /// not GitHub. Goes through NotchPanel.requestOpenFeedback() for the same reason
    /// requestOpenIslandSettings() does (AppDelegate has no SwiftUI environment of its own to call
    /// `openWindow` from directly — see that method's own doc comment). Called by
    /// FallbackMenuView's "Report a Bug / Suggest a Feature…" row.
    func reportBug() {
        panel?.requestOpenFeedback()
    }

    /// Called by FallbackMenuView's "Quit" row.
    func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    /// Called by FallbackMenuView's "Check for Updates…" row. Sparkle shows its own UI for the
    /// rest of the flow (found/not-found/downloading/install prompt) — nothing else to do here.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether to show "Check for Updates…" at all — Sparkle's own recommended guard, since a
    /// manual check while one is already in progress (including the automatic background one)
    /// would either queue confusingly or silently no-op.
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
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

    /// Whether `mode`'s command frame is independently verified — the segmented control and the
    /// menu bar dropdown both gate on this, not just on link readiness, since an unverified
    /// command frame could be sending something other than what it's labeled. False whenever no
    /// profile is actively connected.
    /// For the feedback form's device-context fields — read-only, never touches the headphones.
    var currentProfileDisplayName: String? {
        activeSession?.profile.displayName
    }

    /// Whichever `MenuBar*` template image the status item is currently showing (see
    /// MenuBarIconResolver) — read by FallbackMenuView's own header, so the dropdown leads with
    /// the exact same monochrome glyph the menu bar itself shows, not the full-color AppIcon.
    var currentMenuBarIcon: NSImage? {
        fallbackStatusItem?.button?.image
    }

    func isModeVerified(_ mode: CommandableNoiseMode) -> Bool {
        activeSession?.profile.isModeVerified(mode) ?? false
    }

    func requestNoiseMode(_ mode: CommandableNoiseMode) {
        activeSession?.noiseModeCoordinator.requestMode(mode)
    }

    /// DeviceProfile.isPowerOffVerified's own doc comment — gates ExpandedCard's IconPower button.
    var canPowerOff: Bool {
        activeSession?.profile.isPowerOffVerified ?? false
    }

    /// Sends the power-off command through the exact same WriteGuard/rate-limit/transport path a
    /// noise-mode command goes through (NoiseControlCommander.send). No pending/confirmation
    /// state to track afterward, unlike a noise-mode request: there's no status event to wait for
    /// — the headphones either ack and disconnect, or the write is refused outright.
    func requestPowerOff() {
        guard let profile = activeSession?.profile, profile.isPowerOffVerified, let frame = profile.powerOffCommandFrame else {
            logger.error("Refusing power-off request: not verified for this profile")
            return
        }
        activeSession?.noiseControlCommander.send(frame, label: "power-off")
    }

    /// DeviceProfile.isEqualizerVerified's own doc comment — gates the equalizer UI.
    var canUseEqualizer: Bool {
        activeSession?.profile.isEqualizerVerified ?? false
    }

    /// Sends `preset`'s full transaction and, once it actually goes through, updates
    /// HeadphoneState's own local/optimistic equalizerPreset/equalizerOn — there's no RACE event
    /// to wait for the way noise-mode confirmation has (EqualizerPreset's own doc comment), so
    /// this is the only place either of those two properties ever changes.
    func requestEqualizerPreset(_ preset: EqualizerPreset) {
        guard canUseEqualizer else {
            logger.error("Refusing equalizer-preset request: not verified for this profile")
            return
        }
        Task { [weak self] in
            guard let self, let sent = await self.activeSession?.equalizerCommander.setPreset(preset), sent else { return }
            self.headphoneState.equalizerPreset = preset
            self.headphoneState.equalizerOn = true
        }
    }

    /// Turning the Equalizer off sends `.studio`'s own transaction (no separate "off" transaction
    /// exists — EqualizerPreset's own doc comment) but does NOT touch `equalizerPreset`, so turning
    /// it back on later can restore whichever preset was actually selected, not silently flip to
    /// Studio.
    func requestEqualizerOff() {
        guard canUseEqualizer else {
            logger.error("Refusing equalizer-off request: not verified for this profile")
            return
        }
        Task { [weak self] in
            guard let self, let sent = await self.activeSession?.equalizerCommander.setPreset(.studio), sent else { return }
            self.headphoneState.equalizerOn = false
        }
    }

    /// Turning the Equalizer back on replays whichever preset was last selected (defaulting to
    /// Studio if none has been set this session yet — matches the real device's own default).
    func requestEqualizerOn() {
        requestEqualizerPreset(headphoneState.equalizerPreset ?? .studio)
    }

    var canUseMaxVolumeLimiter: Bool {
        activeSession?.profile.isMaxVolumeLimiterVerified ?? false
    }

    /// Single-frame toggle, same send path as power-off — see DeviceToggle's own doc comment for
    /// why `headphoneState.maxVolumeLimiterOn` only updates once the write actually went through,
    /// and why there's no confirmation to wait for afterward.
    func requestSetMaxVolumeLimiter(_ on: Bool) {
        guard canUseMaxVolumeLimiter else {
            logger.error("Refusing max-volume-limiter request: not verified for this profile")
            return
        }
        guard activeSession?.noiseControlCommander.send(DeviceToggle.maxVolumeLimiter.commandFrame(on: on), label: "max-volume-limiter") == true else { return }
        headphoneState.maxVolumeLimiterOn = on
    }

    var canUseVoicePrompt: Bool {
        activeSession?.profile.isVoicePromptVerified ?? false
    }

    /// Same pattern as `requestSetMaxVolumeLimiter` — DeviceToggle.voicePrompt's own doc comment.
    func requestSetVoicePrompt(_ on: Bool) {
        guard canUseVoicePrompt else {
            logger.error("Refusing voice-prompt request: not verified for this profile")
            return
        }
        guard activeSession?.noiseControlCommander.send(DeviceToggle.voicePrompt.commandFrame(on: on), label: "voice-prompt") == true else { return }
        headphoneState.voicePromptOn = on
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
    ///
    /// `com.apple.preference.bluetooth` was the old System Preferences (pre-Ventura) pane
    /// identifier — System Settings replaced it with `com.apple.BluetoothSettings`, and the old
    /// one no longer resolves to anything specific, so it silently fell back to System Settings'
    /// own General pane instead of Bluetooth. Not formally documented by Apple; confirmed against
    /// the identifiers System Settings' own binary actually exposes, not guessed.
    func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
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
        // equalizerPreset/equalizerOn deliberately NOT reset here — HeadphoneState's own doc
        // comment on why (owner request: the setting should survive a headphones power cycle).
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
