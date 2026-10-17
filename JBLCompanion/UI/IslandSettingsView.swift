import SwiftUI

/// Island/notch tuning controls (silhouette, capsule fit, behavior, position, display), broken
/// out of the menu bar dropdown into its own window.
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

    @AppStorage(IslandSettings.Key.silhouette) private var silhouetteRaw: String = IslandSilhouette.capsule.rawValue
    @AppStorage(IslandSettings.Key.capsuleFitWidth) private var capsuleFitWidth: Double = 0
    @AppStorage(IslandSettings.Key.capsuleFitHeight) private var capsuleFitHeight: Double = 0
    @AppStorage(IslandSettings.Key.capsuleFitDrop) private var capsuleFitDrop: Double = 0
    @AppStorage(IslandSettings.Key.chosenDisplayUUID) private var chosenDisplayUUID: String = ""
    @AppStorage(IslandSettings.Key.autoExpandOnConnect) private var autoExpandOnConnect: Bool = false

    /// Edge is persisted per display (IslandSettings.dockEdge(forDisplayUUID:)), not under one
    /// fixed key, so it can't bind directly to @AppStorage the way every setting above does —
    /// this just mirrors whichever display is currently active, seeded on appear and pushed back
    /// through AppDelegate.setDockEdge on change (which both applies it live and persists it).
    @State private var selectedEdge: DockEdge = .top

    var body: some View {
        Form {
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

            Section("Behavior") {
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
        .onChange(of: silhouetteRaw) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: capsuleFitWidth) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: capsuleFitHeight) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: capsuleFitDrop) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: chosenDisplayUUID) { _, _ in appDelegate.notchSettingsDidChange() }
    }
}
