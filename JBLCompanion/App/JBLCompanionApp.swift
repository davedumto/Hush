import SwiftUI

@main
struct JBLCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showNotchCircle") private var showNotchCircle = true

    @AppStorage(IslandSettings.Key.size) private var islandSizeRaw: String = IslandSize.compact.rawValue
    @AppStorage(IslandSettings.Key.customWidth) private var customWidth: Double = IslandSize.defaultCustomWidth
    @AppStorage(IslandSettings.Key.customHeight) private var customHeight: Double = IslandSize.defaultHeight
    @AppStorage(IslandSettings.Key.silhouette) private var silhouetteRaw: String = IslandSilhouette.capsule.rawValue
    @AppStorage(IslandSettings.Key.capsuleFitWidth) private var capsuleFitWidth: Double = 0
    @AppStorage(IslandSettings.Key.capsuleFitHeight) private var capsuleFitHeight: Double = 0
    @AppStorage(IslandSettings.Key.capsuleFitDrop) private var capsuleFitDrop: Double = 0
    @AppStorage(IslandSettings.Key.cameraFitWidth) private var cameraFitWidth: Double = 0
    @AppStorage(IslandSettings.Key.cameraFitHeight) private var cameraFitHeight: Double = 0
    @AppStorage(IslandSettings.Key.hideMenuBarGap) private var hideMenuBarGap: Bool = true
    @AppStorage(IslandSettings.Key.outline) private var outlineEnabled: Bool = false
    @AppStorage(IslandSettings.Key.chosenDisplayUUID) private var chosenDisplayUUID: String = ""

    var body: some Scene {
        MenuBarExtra {
            menuContent
        } label: {
            Image(systemName: appDelegate.headphoneState.connection == .connected ? "headphones.circle.fill" : "headphones")
        }
        // Back to the default .menu style — a plain native NSMenu, no custom background/border/
        // window-style wrapper.
        .onChange(of: showNotchCircle) { _, newValue in appDelegate.setNotchVisible(newValue) }
        .onChange(of: islandSizeRaw) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: customWidth) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: customHeight) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: silhouetteRaw) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: capsuleFitWidth) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: capsuleFitHeight) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: capsuleFitDrop) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: cameraFitWidth) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: cameraFitHeight) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: hideMenuBarGap) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: outlineEnabled) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: chosenDisplayUUID) { _, _ in appDelegate.notchSettingsDidChange() }
    }

    @ViewBuilder
    private var menuContent: some View {
        let state = appDelegate.headphoneState
        Text(state.connection == .connected ? "Connected: \(state.deviceName)" : "Not connected")
        Text(state.batteryPercent.map { "\($0)%" } ?? "—")
        noiseModeMenuSection
        Divider()
        Toggle("Show notch circle", isOn: $showNotchCircle)
        islandSettingsSection
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

    @ViewBuilder
    private var islandSettingsSection: some View {
        Text("Island").font(.caption).foregroundStyle(.secondary)

        Picker("Size", selection: $islandSizeRaw) {
            Text("Compact").tag(IslandSize.compact.rawValue)
            Text("Spacious").tag(IslandSize.spacious.rawValue)
            Text("Custom").tag(IslandSize.custom.rawValue)
        }
        if islandSizeRaw == IslandSize.custom.rawValue {
            Stepper("Width: \(Int(customWidth))pt", value: $customWidth, in: IslandSize.widthRange, step: 10)
            Stepper("Height: \(Int(customHeight))pt", value: $customHeight, in: IslandSize.heightRange, step: 10)
        }

        Picker("Silhouette", selection: $silhouetteRaw) {
            Text("Capsule").tag(IslandSilhouette.capsule.rawValue)
            Text("Notch").tag(IslandSilhouette.notch.rawValue)
        }

        if silhouetteRaw == IslandSilhouette.capsule.rawValue {
            Text("Capsule fit").font(.caption2).foregroundStyle(.secondary)
            Stepper("Width: \(Int(capsuleFitWidth))pt", value: $capsuleFitWidth, in: IslandCapsuleFit.widthRange, step: 2)
            Stepper("Height: \(Int(capsuleFitHeight))pt", value: $capsuleFitHeight, in: IslandCapsuleFit.heightRange, step: 1)
            Stepper("Drop: \(Int(capsuleFitDrop))pt", value: $capsuleFitDrop, in: IslandCapsuleFit.dropRange, step: 1)
        }

        if appDelegate.isCurrentDisplayNotched {
            Text("Camera fit").font(.caption2).foregroundStyle(.secondary)
            Stepper("Width: \(Int(cameraFitWidth))pt", value: $cameraFitWidth, in: IslandCameraFit.widthRange, step: 1)
            Stepper("Height: \(Int(cameraFitHeight))pt", value: $cameraFitHeight, in: IslandCameraFit.heightRange, step: 1)
        }

        Toggle("Hide menu bar gap", isOn: $hideMenuBarGap)
        Toggle("Outline", isOn: $outlineEnabled)

        Picker("Display", selection: $chosenDisplayUUID) {
            Text("Automatic").tag("")
            ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                Text(screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName)
                    .tag(screen.stableDisplayUUIDString ?? "")
            }
        }
    }
}
