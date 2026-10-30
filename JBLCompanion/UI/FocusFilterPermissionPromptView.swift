import SwiftUI

/// Shown once, ever, by `AppDelegate.showFocusFilterPermissionPromptIfNeeded()` the first time
/// `FocusModeWatcher` can't read `Assertions.json` — there's no native system permission dialog for
/// Full Disk Access (`FocusModeWatcher`'s own doc comment has the confirmation), so this is Hush's
/// own styled stand-in, matching FeedbackView's panel language instead of a bare `NSAlert` sheet.
struct FocusFilterPermissionPromptView: View {
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Brand.orange)
                    .frame(width: 34, height: 34)
                    .background(Theme.Semantic.glassFill, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))

                Text("Switch to ANC with Do Not Disturb")
                    .font(.custom("Fredoka-SemiBold", size: 17))
                    .foregroundStyle(Theme.Semantic.textPrimary)
            }

            Text("Hush can automatically switch your headphones to ANC whenever Do Not Disturb turns on, and restore your previous mode when it turns off. macOS only allows reading the file this relies on with Full Disk Access granted. It's a one-time step, and Hush doesn't use this access for anything else.")
                .font(Theme.Fonts.subText)
                .foregroundStyle(Theme.Semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("Not Now")
                        .font(Theme.Fonts.statusModeName)
                        .foregroundStyle(Theme.Semantic.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Semantic.glassFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onOpenSettings) {
                    Text("Open Settings")
                        .font(Theme.Fonts.statusModeName)
                        .foregroundStyle(Theme.Semantic.pillInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Brand.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(panelGradient)
        .background(Theme.Semantic.cardFrame)
    }

    /// Same radial gradient as ExpandedCard's/FeedbackView's own panel fill —
    /// design/DESIGN_GUIDE.md §4 "Panel fill" — so this reads as part of the same system instead
    /// of a bare macOS dialog.
    private var panelGradient: RadialGradient {
        RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Theme.Semantic.panelHighlight, location: 0),
                .init(color: Theme.Semantic.panelBase, location: 0.56),
                .init(color: Theme.Semantic.panelEdge, location: 1),
            ]),
            center: UnitPoint(x: 0.5, y: 0.28),
            startRadius: 0, endRadius: 360
        )
    }
}
