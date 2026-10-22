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
        // Owner-reported: this window kept opening on every launch. The actual cause: SwiftUI
        // auto-presents a `Window` scene at launch by default unless told not to — true for ANY
        // app's only/first declared Scene, nothing to do with window-restoration state (the
        // NSQuitAlwaysKeepsWindows/isRestorable attempts before this one were both treating the
        // wrong mechanism). Before Island Settings' own Window was removed in favor of the in-tray
        // sheet, ITS Window was the app's first scene and exhibited this same behavior; removing
        // it just made this one the new "only scene," so it inherited the default-launch-open
        // behavior instead. `.defaultLaunchBehavior(.suppressed)` (macOS 14+) is Apple's own
        // documented opt-out for exactly this: an auxiliary window that should only ever appear
        // when explicitly requested (openWindow via NotchPanel.requestOpenFeedback's own token),
        // never automatically.
        Window("Report a Bug / Suggest a Feature", id: FeedbackView.windowID) {
            FeedbackView(appDelegate: appDelegate)
                .background(WindowAccessor { $0.isRestorable = false })
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // No separate Equalizer window (there used to be one) — owner request, 2026-10-22: "I do
        // not want to be opening all those windows." EqualizerControls is embedded directly in
        // ExpandedCard's own in-tray settings sheet instead, reached through the gear icon.
    }
}
