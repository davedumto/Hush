import AppKit
import SwiftUI

/// Content of the fallback NSStatusItem's dropdown — an NSPopover (AppDelegate.toggleFallbackPopover),
/// not a native NSMenu. NSPopover draws its own rounded-rect-with-arrow chrome natively (the "arrow
/// thingy pointing at the menu bar item" look), so this view only needs to fill that chrome with the
/// app's own card styling instead of the system's plain white/dark menu background. Each row sits in
/// its own rounded "glass" card, matching IslandSettingsView's own glassRow look (the owner's own
/// reference for this), not a flat NSMenu-style row-with-divider list. Exactly the same controls the
/// old NSMenu had, minus "Reset Position & Display" — removed (not just restyled): with the island's
/// position now fully user-dragged (corner dock or free-floating, see DockPlacement's own
/// "Free-floating tray direction" section), there's no single "default" position left to reset to
/// the way there was when placement was edge-only.
struct FallbackMenuView: View {
    let appDelegate: AppDelegate
    /// Closure, not a direct call, so this view can close the popover it's hosted in — AppDelegate
    /// owns the NSPopover, not this view.
    let dismiss: () -> Void

    @AppStorage("showNotchCircle") private var showHush: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            row("Island Settings…") {
                appDelegate.openIslandSettings()
                dismiss()
            }

            row("Show Hush", checked: showHush) {
                showHush.toggle()
                appDelegate.setNotchVisible(showHush)
            }

            row("Copy Diagnostics") {
                appDelegate.copyDiagnostics()
                dismiss()
            }
            row("Report a Bug / Suggest a Feature…") {
                appDelegate.reportBug()
                dismiss()
            }

            if appDelegate.canCheckForUpdates {
                row("Check for Updates…") {
                    appDelegate.checkForUpdates()
                    dismiss()
                }
            }

            #if DEBUG
            if !appDelegate.debugTestableModes.isEmpty {
                Text("DEBUG".uppercased())
                    .font(Theme.Fonts.eyebrow)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 4)
                ForEach(appDelegate.debugTestableModes, id: \.self) { mode in
                    row("Send test frame: \(mode.displayText)") {
                        appDelegate.sendDebugTestFrame(mode)
                        dismiss()
                    }
                }
            }
            #endif

            row("Quit", shortcut: "⌘Q") {
                appDelegate.quitApp()
            }
        }
        .padding(12)
        .frame(width: 300)
        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
    }

    /// The app icon, centered at the top of the dropdown — the owner's own reference, Vorssaint's
    /// dropdown, leads with its icon the same way instead of a text title.
    private var header: some View {
        HStack {
            Spacer()
            if let icon = appDelegate.currentMenuBarIcon {
                // The menu bar icon is already a template image (MenuBarIconResolver's own
                // assets, isTemplate = true — see AppDelegate.updateMenuBarIcon) — SwiftUI's
                // .template rendering mode + foregroundStyle is what lets a single asset tint to
                // plain white here, the same way macOS tints it for the menu bar itself.
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            Spacer()
        }
        .padding(.bottom, 2)
    }

    /// Plain white, not Theme.Brand.orange — this dropdown is deliberately monochrome (owner
    /// reference: Vorssaint's own dropdown), unlike the rest of the app's BrandOrange-accented
    /// surfaces. Scoped to this one view, not a Theme change, so the card/feedback form/settings
    /// window keep their own brand color untouched.
    private static let accent = Color.white

    /// One glass-stroked row — matches IslandSettingsView's own `glassRow`, so this dropdown
    /// reads as the same system as the rest of the app instead of a bare macOS menu. `joined`
    /// rows (the diagnostics/report pair, the DEBUG test-frame list) share a flat seam instead of
    /// each getting its own full rounded rect, matching the owner's own reference image.
    private func row(
        _ title: String, checked: Bool = false, shortcut: String? = nil,
        corners: UIRectCorner = .allCorners, joined: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Self.accent)
                        .frame(width: 12)
                } else {
                    Color.clear.frame(width: 12)
                }
                Text(title)
                    .font(Theme.Fonts.subText)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(Theme.Fonts.statusDetail)
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(FallbackRowButtonStyle(corners: corners, joined: joined))
    }
}

/// A glass card background behind each row, plus a faint highlight while pressed — NSMenu's own
/// hover highlight equivalent, since this is a plain SwiftUI Button, not a real NSMenuItem.
private struct FallbackRowButtonStyle: ButtonStyle {
    let corners: UIRectCorner
    let joined: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedCorners(radius: 10, corners: corners)
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.22 : 0.13))
            .clipShape(shape)
            .overlay(shape.stroke(Color.white.opacity(joined ? 0 : 0.12), lineWidth: 1))
    }
}

/// AppKit's `UIRectCorner`/rounded-per-corner shape has no AppKit equivalent built in —
/// `RoundedRectangle` only offers all four corners alike. Used to flatten the seam between two
/// stacked "joined" rows, same as IslandSettingsView's own copy of this shape.
private struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Mirrors AppKit's `NSRectCorner`-adjacent flag set (there's no built-in SwiftUI equivalent) —
/// same copy as IslandSettingsView's own private one, kept file-local rather than shared since
/// neither file is meant to depend on the other.
private struct UIRectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
