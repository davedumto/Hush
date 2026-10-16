import SwiftUI
import os.log

@main
struct JBLCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showNotchCircle") private var showNotchCircle = true
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "JBLCompanionApp")

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            // SwiftUI gives MenuBarExtra no direct "the status item was created" hook, so this
            // onAppear is the closest available confirmation that the scene actually rendered —
            // if this log line is ever missing from a launch where the icon doesn't show, that
            // points at MenuBarExtra itself failing to render rather than something downstream.
            Image(systemName: appDelegate.headphoneState.connection == .connected ? "headphones.circle.fill" : "headphones")
                .onAppear { logger.info("MenuBarExtra label appeared (status item should be visible now)") }
        }
        // Back to the default .menu style — a plain native NSMenu, no custom background/border/
        // window-style wrapper.
        .onChange(of: showNotchCircle) { _, newValue in appDelegate.setNotchVisible(newValue) }

        // A real window, not part of the menu's own NSMenu — see IslandSettingsView's own doc
        // comment for why the steppers it hosts need to live outside the dropdown.
        Window("Island Settings", id: IslandSettingsView.windowID) {
            IslandSettingsView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
    }

    @ViewBuilder
    private var menuContent: some View {
        let state = appDelegate.headphoneState
        Text(state.connection == .connected ? "Connected: \(state.deviceName)" : "Not connected")
        Text(state.batteryPercent.map { "\($0)%" } ?? "—")
        noiseModeMenuSection
        Divider()
        Toggle("Show notch circle", isOn: $showNotchCircle)
        IslandSettingsMenuButton()
        Button("Copy Diagnostics") {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(appDelegate.diagnosticsText(), forType: .string)
        }
        #if DEBUG
        Divider()
        debugSection
        #endif
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var noiseModeMenuSection: some View {
        let state = appDelegate.headphoneState
        if let pending = state.pendingNoiseMode {
            Text("Noise mode: Pending \(pending.displayText)…")
        } else if state.noiseModeConfirmationTimedOut {
            Text("Noise mode: no confirmation")
        } else {
            Text("Noise mode: \(state.noiseMode.displayText)")
        }
        ForEach(CommandableNoiseMode.allCases, id: \.self) { mode in
            Button(mode.displayText) { appDelegate.requestNoiseMode(mode) }
                .disabled(state.pendingNoiseMode != nil || !appDelegate.isModeVerified(mode))
        }
    }

    #if DEBUG
    /// Hidden outside DEBUG builds entirely (not just visually — the whole section is compiled
    /// out). Sends only whichever mode(s) are currently verified, through the exact same
    /// WriteGuard/rate-limit/confirmation-timeout path as a normal tap, and shows the next 5 RACE
    /// events so a mode's real on-device effect can be checked by hand.
    @ViewBuilder
    private var debugSection: some View {
        let state = appDelegate.headphoneState
        Text("Debug").font(.caption).foregroundStyle(.secondary)
        ForEach(appDelegate.debugTestableModes, id: \.self) { mode in
            Button("Send test frame: \(mode.displayText)") { appDelegate.sendDebugTestFrame(mode) }
                .disabled(state.pendingNoiseMode != nil)
        }
        if !state.debugRecentEvents.isEmpty {
            ForEach(Array(state.debugRecentEvents.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    #endif
}
