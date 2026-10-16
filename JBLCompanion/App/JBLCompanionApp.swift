import SwiftUI

@main
struct JBLCompanionApp: App {
    var body: some Scene {
        MenuBarExtra("JBL Companion", systemImage: "headphones") {
            Text("Not connected")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
