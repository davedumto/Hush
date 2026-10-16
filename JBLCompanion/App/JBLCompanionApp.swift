import SwiftUI

@main
struct JBLCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showNotchCircle") private var showNotchCircle = true
    @AppStorage("notchOffset") private var notchOffset: Double = 140

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            Image(systemName: appDelegate.headphoneState.connection == .connected ? "headphones.circle.fill" : "headphones")
        }
        .onChange(of: showNotchCircle) { _, newValue in
            appDelegate.setNotchVisible(newValue)
        }
        .onChange(of: notchOffset) { _, _ in
            appDelegate.repositionNotch()
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        let state = appDelegate.headphoneState
        Text(state.connection == .connected ? "Connected: \(state.deviceName)" : "Not connected")
        Text(state.batteryPercent.map { "\($0)%" } ?? "—")
        Text("Noise mode: \(state.noiseMode.displayText)")
        Divider()
        Toggle("Show notch circle", isOn: $showNotchCircle)
        VStack(alignment: .leading) {
            Text("Notch offset: \(Int(notchOffset))pt")
            Slider(value: $notchOffset, in: 40...300, step: 10)
        }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
