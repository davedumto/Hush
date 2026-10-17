import SwiftUI

/// Island/notch tuning controls (size, silhouette, capsule/camera fit, behavior, display),
/// broken out of the menu bar dropdown into its own window.
///
/// The dropdown is a native NSMenu (`.menu` style MenuBarExtra). `Toggle`/`Picker`/`Button` map
/// onto native NSMenuItem equivalents there, which NSMenu handles natively — but `Stepper` has no
/// native menu-item equivalent, so SwiftUI has to host it as a custom view inside the menu. Each
/// tap changes an `@AppStorage` value, which rebuilds the whole menu's item list while NSMenu is
/// still tracking that click, and that's what was closing the dropdown on every increment/
/// decrement. A real window has no tracking session for that rebuild to interrupt, so moving the
/// steppers (and the rest of this section, for one coherent surface) here removes the bug
/// entirely instead of working around it.
struct IslandSettingsView: View {
    static let windowID = "island-settings"

    let appDelegate: AppDelegate

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
    @AppStorage(IslandSettings.Key.autoExpandOnConnect) private var autoExpandOnConnect: Bool = false

    /// Edge is persisted per display (IslandSettings.dockEdge(forDisplayUUID:)), not under one
    /// fixed key, so it can't bind directly to @AppStorage the way every setting above does —
    /// this just mirrors whichever display is currently active, seeded on appear and pushed back
    /// through AppDelegate.setDockEdge on change (which both applies it live and persists it).
    @State private var selectedEdge: DockEdge = .top

    var body: some View {
        Form {
            Section("Size") {
                Picker("Size", selection: $islandSizeRaw) {
                    Text("Compact").tag(IslandSize.compact.rawValue)
                    Text("Spacious").tag(IslandSize.spacious.rawValue)
                    Text("Custom").tag(IslandSize.custom.rawValue)
                }
                if islandSizeRaw == IslandSize.custom.rawValue {
                    Stepper("Width: \(Int(customWidth))pt", value: $customWidth, in: IslandSize.widthRange, step: 10)
                    Stepper("Height: \(Int(customHeight))pt", value: $customHeight, in: IslandSize.heightRange, step: 10)
                }
            }

            Section("Silhouette") {
                Picker("Silhouette", selection: $silhouetteRaw) {
                    Text("Capsule").tag(IslandSilhouette.capsule.rawValue)
                    Text("Notch").tag(IslandSilhouette.notch.rawValue)
                }
                if silhouetteRaw == IslandSilhouette.capsule.rawValue {
                    Stepper("Width: \(Int(capsuleFitWidth))pt", value: $capsuleFitWidth, in: IslandCapsuleFit.widthRange, step: 2)
                    Stepper("Height: \(Int(capsuleFitHeight))pt", value: $capsuleFitHeight, in: IslandCapsuleFit.heightRange, step: 1)
                    Stepper("Drop: \(Int(capsuleFitDrop))pt", value: $capsuleFitDrop, in: IslandCapsuleFit.dropRange, step: 1)
                }
            }

            if appDelegate.isCurrentDisplayNotched {
                Section("Camera fit") {
                    Stepper("Width: \(Int(cameraFitWidth))pt", value: $cameraFitWidth, in: IslandCameraFit.widthRange, step: 1)
                    Stepper("Height: \(Int(cameraFitHeight))pt", value: $cameraFitHeight, in: IslandCameraFit.heightRange, step: 1)
                }
            }

            Section("Behavior") {
                Toggle("Hide menu bar gap", isOn: $hideMenuBarGap)
                Toggle("Outline", isOn: $outlineEnabled)
                Toggle("Auto-expand on connect", isOn: $autoExpandOnConnect)
            }

            Section("Position") {
                Picker("Edge", selection: $selectedEdge) {
                    Text("Top").tag(DockEdge.top)
                    Text("Bottom").tag(DockEdge.bottom)
                    Text("Left").tag(DockEdge.left)
                    Text("Right").tag(DockEdge.right)
                }
            }

            Section("Display") {
                Picker("Display", selection: $chosenDisplayUUID) {
                    Text("Automatic").tag("")
                    ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                        Text(screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName)
                            .tag(screen.stableDisplayUUIDString ?? "")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .onAppear { selectedEdge = appDelegate.currentDockEdge }
        .onChange(of: selectedEdge) { _, newEdge in appDelegate.setDockEdge(newEdge) }
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
}

/// The dropdown's entry point into the Island Settings window. A separate small view purely so it
/// can read `openWindow` from the environment — the MenuBarExtra content closure lives inside
/// `JBLCompanionApp`, a Scene builder, which can't hold `@Environment` directly.
struct IslandSettingsMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Island Settings…") {
            // This is an accessory (LSUIElement) app with no Dock icon — without activating
            // first, a newly opened window can appear behind whatever app was frontmost.
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: IslandSettingsView.windowID)
        }
    }
}
