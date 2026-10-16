import SwiftUI

@main
struct JBLCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showNotchCircle") private var showNotchCircle = true

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            Image(systemName: appDelegate.headphoneState.connection == .connected ? "headphones.circle.fill" : "headphones")
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
                .disabled(state.pendingNoiseMode != nil)
        }
    }
}
