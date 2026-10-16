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
        .onChange(of: showNotchCircle) { _, newValue in
            appDelegate.setNotchVisible(newValue)
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
        positionSection
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var positionSection: some View {
        if let positionState = appDelegate.notchPositionState {
            let position = positionState.position
            Text("Position").font(.caption).foregroundStyle(.secondary)
            Stepper(
                "X: \(Int(position.x))pt",
                onIncrement: { appDelegate.setNotchPosition(NotchPosition(x: position.x + 10, y: position.y)) },
                onDecrement: { appDelegate.setNotchPosition(NotchPosition(x: position.x - 10, y: position.y)) }
            )
            Stepper(
                "Y: \(Int(position.y))pt",
                onIncrement: { appDelegate.setNotchPosition(NotchPosition(x: position.x, y: position.y + 10)) },
                onDecrement: { appDelegate.setNotchPosition(NotchPosition(x: position.x, y: position.y - 10)) }
            )
            Button("Reset position") { appDelegate.resetNotchPosition() }
        }
    }
}
