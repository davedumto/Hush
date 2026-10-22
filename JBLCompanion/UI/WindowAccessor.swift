import SwiftUI

/// Reaches the underlying `NSWindow` for a SwiftUI `Window(_:id:)` scene, which otherwise has no
/// direct handle — SwiftUI only exposes `restorationBehavior` (the SwiftUI-level opt-out of
/// window restoration) starting macOS 15, and this project's deployment target is 14. `NSWindow`'s
/// own `isRestorable` flag is the lower-level mechanism `restorationBehavior` is itself built on
/// (Apple's AppKit restoration docs), available on every macOS version this app supports, so this
/// reaches it directly instead of bumping the deployment target for one modifier.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // The view isn't attached to its window yet on this very first call (SwiftUI hasn't
        // inserted it into the hierarchy), so `view.window` is still nil here — queue the
        // configure call for the next run loop turn, by which point it is.
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { configure(window) }
    }
}
