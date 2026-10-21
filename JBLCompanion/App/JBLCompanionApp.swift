import SwiftUI
import os.log

/// No MenuBarExtra scene — AppDelegate's own plain AppKit NSStatusItem (set up in
/// applicationDidFinishLaunching) is the app's one and only menu bar item. Two status items for
/// one app was a real bug, not a deliberate fallback/primary split: MenuBarExtra used to also
/// create its own, with a richer dropdown (device/battery, noise-mode buttons, an Island Settings
/// button, a notch-circle toggle). That functionality's two genuinely non-duplicated pieces moved
/// elsewhere rather than being lost: Island Settings is reachable both from the gear icon in
/// ExpandedCard's own top row (ExpandedCard.openIslandSettings) and from the fallback menu's own
/// "Island Settings…" item (AppDelegate.openIslandSettingsFromFallback, which goes through
/// NotchPanel.requestOpenIslandSettings — see that property's own doc comment for why AppDelegate
/// can't just call `openWindow` itself), and the fallback menu already had its own equivalent
/// "Show Hush" action. The rest (mode buttons, battery, device name) was a duplicate of what the
/// expanded card itself already shows.
@main
struct JBLCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A real window, not part of any menu — see IslandSettingsView's own doc comment for why
        // the steppers it hosts need to live outside a dropdown. Opened via
        // ExpandedCard.openIslandSettings (the gear icon in the card's own top row) or the
        // fallback menu's "Island Settings…" item.
        Window("Island Settings", id: IslandSettingsView.windowID) {
            IslandSettingsView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)

        // Opened via the fallback menu's "Report a Bug / Suggest a Feature…" item — see
        // NotchPanel.requestOpenFeedback()'s own doc comment for why it goes through a token
        // instead of calling openWindow directly.
        Window("Report a Bug / Suggest a Feature", id: FeedbackView.windowID) {
            FeedbackView(appDelegate: appDelegate)
        }
        .windowResizability(.contentSize)
    }
}
