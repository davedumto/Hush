import SwiftUI
import os.log

/// No MenuBarExtra scene — AppDelegate's own plain AppKit NSStatusItem (set up in
/// applicationDidFinishLaunching) is the app's one and only menu bar item. Two status items for
/// one app was a real bug, not a deliberate fallback/primary split: MenuBarExtra used to also
/// create its own, with a richer dropdown (device/battery, noise-mode buttons, an Island Settings
/// button, a notch-circle toggle). That functionality's two genuinely non-duplicated pieces moved
/// elsewhere rather than being lost: Island Settings now lives only in the tray (ExpandedCard's
/// own in-tray sheet, reached via its gear icon, or via the fallback menu's "Island Settings…"
/// item — AppDelegate.openIslandSettingsFromFallback, which goes through
/// NotchPanel.requestOpenIslandSettings — owner request, 2026-10-22: "the only island setting we
/// have is on the island," removing the separate window that used to also exist), and the
/// fallback menu already had its own equivalent "Show Hush" action. The rest (mode buttons,
/// battery, device name) was a duplicate of what the expanded card itself already shows.
@main
struct JBLCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Opened via the fallback menu's "Report a Bug / Suggest a Feature…" item — see
        // NotchPanel.requestOpenFeedback()'s own doc comment for why it goes through a token
        // instead of calling openWindow directly.
        Window("Report a Bug / Suggest a Feature", id: FeedbackView.windowID) {
            FeedbackView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)

        // No separate Equalizer window (there used to be one) — owner request, 2026-10-22: "I do
        // not want to be opening all those windows." EqualizerControls is embedded directly in
        // ExpandedCard's own in-tray settings sheet instead, reached through the gear icon.
    }
}
