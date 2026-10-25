import ServiceManagement
import SwiftUI

/// Island/notch tuning controls (pill size, behavior, display) — embedded in ExpandedCard's own
/// in-tray settings sheet, the only place this lives now (owner request, 2026-10-22: "the external
/// island setting is still implemented, can you remove it... the only island setting we have is on
/// the island" — this used to also have its own standalone window, reachable both from the card's
/// gear icon and the fallback menu bar's "Island Settings…" item; the window is gone, and the
/// fallback menu item now opens the tray straight to this same sheet instead
/// (NotchPanel.requestOpenIslandSettings's own doc comment)). Dock edge and distance-from-edge are
/// set entirely by dragging the island itself, not from here — a manual edge/margin picker here
/// could only ever cover a subset of what dragging already does, and its "distance from edge" had
/// no meaning at all while free-floating.
struct IslandSettingsControls: View {
    let onSettingsChanged: () -> Void
    /// Owner spec, 2026-10-25 — see IslandSettings.NotchAttachmentMode's own doc comment. Both
    /// hardware-read-only (not @AppStorage-backed the way the other rows are): "which display" and
    /// "does it have a real notch" are live facts about the currently active display, not stored
    /// preferences themselves — only the *chosen mode* for that display's UUID is actually stored.
    var hasRealNotchOnCurrentDisplay: Bool = false
    var currentDisplayUUID: String? = nil

    @AppStorage(IslandSettings.Key.pillDiameter) private var pillDiameter: Double = Double(DockPlacement.collapsedPillDiameter)
    @AppStorage(IslandSettings.Key.chosenDisplayUUID) private var chosenDisplayUUID: String = ""
    @AppStorage(IslandSettings.Key.autoExpandOnConnect) private var autoExpandOnConnect: Bool = false

    /// Mirrors SMAppService.mainApp's own live registration status — not @AppStorage-backed: the
    /// real source of truth lives outside UserDefaults entirely here (in Login Items), so this is
    /// seeded on appear and pushed back through SMAppService on change, rather than bound directly.
    @State private var launchAtLogin: Bool = false
    /// Seeded on appear from IslandSettings.notchAttachmentMode(forDisplayUUID:) (keyed by
    /// `currentDisplayUUID`, same reasoning as `launchAtLogin` above — the real per-display stored
    /// value isn't a single fixed @AppStorage key, so it can't bind directly either), then written
    /// straight back through IslandSettings on change.
    @State private var notchAttachmentMode: IslandSettings.NotchAttachmentMode = .notch

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if hasRealNotchOnCurrentDisplay {
                sectionLabel("Notch")
                glassRow { notchAttachmentRow }
            }

            sectionLabel("Pill size")
            glassRow { pillSizeRow }

            sectionLabel("Behavior")
            VStack(spacing: 1) {
                glassRow(corners: [.topLeft, .topRight], joined: true) { autoExpandRow }
                glassRow(corners: [.bottomLeft, .bottomRight], joined: true) { launchAtLoginRow }
            }

            sectionLabel("Display")
            glassRow { displayRow }
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if let currentDisplayUUID {
                notchAttachmentMode = IslandSettings.notchAttachmentMode(forDisplayUUID: currentDisplayUUID)
            }
        }
        .onChange(of: pillDiameter) { _, _ in onSettingsChanged() }
        .onChange(of: chosenDisplayUUID) { _, _ in onSettingsChanged() }
        .onChange(of: notchAttachmentMode) { _, newValue in
            guard let currentDisplayUUID else { return }
            IslandSettings.setNotchAttachmentMode(newValue, forDisplayUUID: currentDisplayUUID)
            onSettingsChanged()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // The system refused (e.g. not yet approved in System Settings > Login Items) —
                // reflect what's actually registered rather than a toggle that silently lied.
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var notchAttachmentRow: some View {
        HStack {
            Text("Attachment")
                .font(Theme.Fonts.subText)
                .foregroundStyle(Theme.Semantic.textPrimary)
            Spacer()
            Picker("", selection: $notchAttachmentMode) {
                Text("Notch").tag(IslandSettings.NotchAttachmentMode.notch)
                Text("Island").tag(IslandSettings.NotchAttachmentMode.island)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
        }
    }

    private var pillSizeRow: some View {
        HStack {
            Text("Diameter: \(Int(pillDiameter))pt")
                .font(Theme.Fonts.subText)
                .foregroundStyle(Theme.Semantic.textPrimary)
            Spacer()
            Stepper(
                "", value: $pillDiameter,
                in: Double(DockPlacement.pillDiameterRange.lowerBound)...Double(DockPlacement.pillDiameterRange.upperBound), step: 4
            )
            .labelsHidden()
        }
    }

    private var autoExpandRow: some View {
        HStack {
            Text("Auto-expand on connect")
                .font(Theme.Fonts.subText)
                .foregroundStyle(Theme.Semantic.textPrimary)
            Spacer()
            OrangeToggle(isOn: $autoExpandOnConnect)
        }
    }

    private var launchAtLoginRow: some View {
        HStack {
            Text("Launch at Login")
                .font(Theme.Fonts.subText)
                .foregroundStyle(Theme.Semantic.textPrimary)
            Spacer()
            OrangeToggle(isOn: $launchAtLogin)
        }
    }

    private var displayRow: some View {
        HStack {
            Text("Display")
                .font(Theme.Fonts.subText)
                .foregroundStyle(Theme.Semantic.textPrimary)
            Spacer()
            Picker("", selection: $chosenDisplayUUID) {
                Text("Automatic").tag("")
                ForEach(Array(NSScreen.screens.enumerated()), id: \.offset) { index, screen in
                    Text(screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName)
                        .tag(screen.stableDisplayUUIDString ?? "")
                }
            }
            .labelsHidden()
            .tint(Theme.Semantic.textSecondary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Theme.Fonts.eyebrow)
            .foregroundStyle(Theme.Semantic.textSecondary)
    }

    /// One glass-stroked row — matches FeedbackView's own field chrome, so settings reads as the
    /// same system as the feedback form and the card itself, not a bare macOS Form/Picker.
    /// `joined` rows (the "Behavior" group) share a flat seam between them instead of each getting
    /// its own full rounded rect, matching the reference image's two-row grouped look.
    private func glassRow<Content: View>(
        corners: UIRectCorner = .allCorners, joined: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        let strokeWidth: CGFloat = joined ? 0 : 1
        let shape = RoundedCorners(radius: 10, corners: corners)
        let border: some View = shape.stroke(Theme.Semantic.glassStroke, lineWidth: strokeWidth)
        return HStack {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.Semantic.glassFill)
        .clipShape(shape)
        .overlay(border)
    }
}

/// AppKit's `UIRectCorner`/rounded-per-corner shape has no AppKit equivalent built in —
/// `RoundedRectangle` only offers all four corners alike. Used by `glassRow` to flatten the seam
/// between two stacked "joined" rows.
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
/// just enough for `RoundedCorners` above.
private struct UIRectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
