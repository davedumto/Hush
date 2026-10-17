import SwiftUI

/// Island/notch tuning controls (pill size, behavior, position, display), broken out of the menu
/// bar dropdown into its own window.
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

    @AppStorage(IslandSettings.Key.pillDiameter) private var pillDiameter: Double = Double(DockPlacement.collapsedPillDiameter)
    @AppStorage(IslandSettings.Key.chosenDisplayUUID) private var chosenDisplayUUID: String = ""
    @AppStorage(IslandSettings.Key.autoExpandOnConnect) private var autoExpandOnConnect: Bool = false

    /// Edge is persisted per display (IslandSettings.dockEdge(forDisplayUUID:)), not under one
    /// fixed key, so it can't bind directly to @AppStorage the way every setting above does —
    /// this just mirrors whichever display is currently active, seeded on appear and pushed back
    /// through AppDelegate.setDockEdge on change (which both applies it live and persists it).
    @State private var selectedEdge: DockEdge = .top
    /// Same reasoning as `selectedEdge` — IslandSettings.edgeMargin(for:) is keyed per edge, not
    /// one fixed @AppStorage key, so this mirrors whichever edge is currently selected above:
    /// reseeded every time `selectedEdge` changes, pushed back through
    /// IslandSettings.setEdgeMargin(_:for:) on its own change.
    @State private var edgeMargin: Double = Double(DockPlacement.edgeMargin(for: .top))

    var body: some View {
        Form {
            Section("Pill size") {
                Stepper(
                    "Diameter: \(Int(pillDiameter))pt", value: $pillDiameter,
                    in: Double(DockPlacement.pillDiameterRange.lowerBound)...Double(DockPlacement.pillDiameterRange.upperBound), step: 4
                )
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
                Stepper(
                    "Distance from \(selectedEdge.rawValue): \(Int(edgeMargin))pt", value: $edgeMargin,
                    in: Double(DockPlacement.edgeMarginRange.lowerBound)...Double(DockPlacement.edgeMarginRange.upperBound), step: 4
                )
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
        .onAppear {
            selectedEdge = appDelegate.currentDockEdge
            edgeMargin = Double(IslandSettings.edgeMargin(for: selectedEdge))
        }
        .onChange(of: selectedEdge) { _, newEdge in
            appDelegate.setDockEdge(newEdge)
            // Show *that* edge's own saved margin, not whatever the previous edge's was.
            edgeMargin = Double(IslandSettings.edgeMargin(for: newEdge))
        }
        .onChange(of: edgeMargin) { _, newValue in
            IslandSettings.setEdgeMargin(CGFloat(newValue), for: selectedEdge)
            appDelegate.notchSettingsDidChange()
        }
        .onChange(of: pillDiameter) { _, _ in appDelegate.notchSettingsDidChange() }
        .onChange(of: chosenDisplayUUID) { _, _ in appDelegate.notchSettingsDidChange() }
    }
}
