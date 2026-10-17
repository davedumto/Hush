import SwiftUI

/// The expanded card — design/DESIGN_GUIDE.md §4. Only the top dock is reachable from the live
/// app today (NotchPanel has no left/right/bottom placement logic yet, same limitation as
/// CollapsedPill's own doc comment describes); bottom/left/right are fully built and
/// tested/previewed but not wired into real app state.
///
/// Mode buttons are explicitly out of scope for this stage — `modeControls` is a clearly marked
/// slot the caller fills with the existing segmented control/status caption, completely unchanged,
/// so the app keeps working exactly as before. A later stage replaces what's passed into that slot.
struct ExpandedCard<ModeControls: View>: View {
    let state: HeadphoneState
    let dock: CardDock
    let onCollapseTapped: () -> Void
    @ViewBuilder let modeControls: () -> ModeControls

    @Environment(\.colorScheme) private var colorScheme

    private var isVertical: Bool { dock.isVertical }
    private var cardSize: CGSize {
        isVertical ? CGSize(width: 296, height: 470) : CGSize(width: 374, height: 470)
    }
    private var heroHeight: CGFloat { isVertical ? 196 : 236 }
    private var photoHeight: CGFloat { isVertical ? 168 : 206 }
    private var modelNumberFontSize: CGFloat { isVertical ? 112 : 150 }
    private var tabLengthAlongEdge: CGFloat { isVertical ? 92 : 116 }
    private var tabDepthIntoPanel: CGFloat { isVertical ? 30 : 32 }

    private var content: ExpandedCardContent {
        ExpandedCardContent.resolve(connection: state.connection, batteryPercent: state.batteryPercent)
    }

    var body: some View {
        ZStack {
            frame
            panelContent
            tab
        }
        .frame(width: cardSize.width, height: cardSize.height)
    }

    // MARK: - Frame + panel

    private var frame: some View {
        RoundedRectangle(cornerRadius: 33, style: .continuous)
            .fill(Theme.Semantic.cardFrame)
            .shadow(
                color: colorScheme == .dark ? .clear : Theme.Brand.black.opacity(0.6),
                radius: 30, x: 0, y: 30
            )
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            heroSection
            nameBlock
                .padding(.top, 10)
            modeControls()
                .padding(.top, 12)
            footer
                .padding(.top, 12)
        }
        .padding(panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelGradient, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .padding(7)
    }

    /// §4 "Panel padding on the docked side": extra room on the edge the tab occupies, so content
    /// never sits under it.
    private var panelPadding: EdgeInsets {
        switch dock {
        case .top: return EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        case .bottom: return EdgeInsets(top: 14, leading: 14, bottom: 10, trailing: 14)
        case .left: return EdgeInsets(top: 14, leading: 38, bottom: 14, trailing: 14)
        case .right: return EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 38)
        }
    }

    /// §4 "Panel fill": radial gradient, centre x50% y28%, stops PanelHighlight 0 / PanelBase
    /// 0.56 / PanelEdge 1, end radius about the card height.
    private var panelGradient: RadialGradient {
        RadialGradient(
            gradient: Gradient(stops: [
                .init(color: Theme.Semantic.panelHighlight, location: 0),
                .init(color: Theme.Semantic.panelBase, location: 0.56),
                .init(color: Theme.Semantic.panelEdge, location: 1),
            ]),
            center: UnitPoint(x: 0.5, y: 0.28),
            startRadius: 0, endRadius: cardSize.height
        )
    }

    // MARK: - Tab

    @ViewBuilder
    private var tab: some View {
        let shape = CutoutTabShape(dock: dock, lengthAlongEdge: tabLengthAlongEdge, depthIntoPanel: tabDepthIntoPanel)
        shape
            .fill(Theme.Semantic.cardFrame)
            .overlay(alignment: tabContentAlignment) {
                tabContent
                    .padding(tabContentPadding)
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .contentShape(shape)
            .onTapGesture { onCollapseTapped() }
    }

    private var tabContentAlignment: Alignment {
        switch dock {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private var tabContentPadding: EdgeInsets {
        // Centers the mark (+wordmark) within the tab's own depth, roughly — the tab's depth is
        // small (30-32pt) so a modest fixed inset reads correctly without per-dock measurement.
        switch dock {
        case .top: return EdgeInsets(top: 7, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: 7, trailing: 0)
        case .left: return EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0)
        case .right: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        let markColor = colorScheme == .dark ? Color.white : Theme.Brand.navy
        if isVertical {
            // §4: "Content | HushMark 20 only" on side docks.
            markGlyph(size: 20, color: markColor)
        } else {
            HStack(spacing: 6) {
                markGlyph(size: 18, color: markColor)
                Text("hush.")
                    .font(Theme.Fonts.tabWordmark)
                    .foregroundStyle(markColor)
                + Text(".").foregroundStyle(Theme.Brand.orange).font(Theme.Fonts.tabWordmark)
            }
        }
    }

    /// HushArchTemplate (tintable) + a hand-drawn orange dot, same technique CollapsedPill uses —
    /// HushMark's own flattened asset always renders its dot at full orange, which is fine here
    /// (the tab's mark is never dimmed), but reusing the template keeps the tint correct in both
    /// themes without a second asset variant.
    private func markGlyph(size: CGFloat, color: Color) -> some View {
        ZStack {
            Image("HushArchTemplate")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
            Circle()
                .fill(Theme.Brand.orange)
                .frame(width: size * (7.4 / 32), height: size * (7.4 / 32))
                .offset(y: size * ((20.5 - 16) / 32))
        }
        .frame(width: size, height: size)
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(spacing: 8) {
            modelChip
            Spacer(minLength: 0)
            iconButton("IconSettings")
            iconButton("IconPower")
        }
    }

    @ViewBuilder
    private var modelChip: some View {
        if !state.modelNumberText.isEmpty {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.Brand.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.Brand.orange.opacity(0.85), radius: 4.5)
                Text(state.modelNumberText)
                    .font(Theme.Fonts.modelChip)
                    .foregroundStyle(Theme.Semantic.chipInk)
            }
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Theme.Semantic.chipFill, in: Capsule())
        }
    }

    private func iconButton(_ assetName: String) -> some View {
        Circle()
            .strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1)
            .frame(width: 28, height: 28)
            .overlay(
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white)
            )
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear

            // §4 hero layers, back to front.
            if colorScheme == .dark {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Theme.Brand.orange.opacity(0.42), Theme.Brand.orange.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 130)
                    .blur(radius: 8)
                    .position(x: (cardSize.width - 28) / 2, y: heroHeight * 0.58)
            } else {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [Theme.Brand.black.opacity(0.45), Theme.Brand.black.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 26)
                    .position(x: (cardSize.width - 28) / 2, y: heroHeight - 13)
            }

            modelNumberView
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 4)

            photoView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .overlay(alignment: .bottomLeading) { hotspot }

            batteryChip
                .padding(.bottom, isVertical ? 6 : 18)
        }
        .frame(height: heroHeight)
    }

    private var modelNumberView: some View {
        Text(ExpandedCardContent.heroNumberText(from: state.modelNumberText))
            .font(Theme.Fonts.modelNumber(sideDock: isVertical))
            .tracking(-7.5)
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.Semantic.modelNumberTop, Theme.Semantic.modelNumberBottom],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .opacity(state.modelNumberText.isEmpty ? 0 : 1)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private var photoView: some View {
        if let assetName = currentPhotoAssetName {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: photoHeight)
                .shadow(color: Theme.Brand.black.opacity(0.55), radius: 13, x: 0, y: 11)
        } else {
            // CLAUDE.md / §4: unknown models use the HushMark with no photo.
            markGlyph(size: 118, color: colorScheme == .dark ? .white.opacity(0.32) : Theme.Brand.navy.opacity(0.32))
                .frame(height: photoHeight)
        }
    }

    /// Contrast flip (§3/§4): black photo in dark theme, white photo in light theme.
    private var currentPhotoAssetName: String? {
        guard let names = state.photoAssetNames else { return nil }
        return colorScheme == .dark ? names.black : names.white
    }

    private var hotspot: some View {
        Circle()
            .fill(Theme.Semantic.glassFill)
            .overlay(Circle().strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))
            .frame(width: 22, height: 22)
            .overlay(
                Image("IconPlus")
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                    .foregroundStyle(.white)
            )
            .offset(x: (cardSize.width - panelPadding.leading - panelPadding.trailing) * (isVertical ? 0.14 : 0.22), y: -heroHeight * 0.38)
    }

    private var batteryChip: some View {
        Group {
            switch content.batteryChip {
            case .none:
                EmptyView()
            case .normal(let percent):
                batteryChipBody(eyebrow: "BATTERY", value: "\(percent)%", fraction: Double(percent) / 100, isLow: false)
            case .low(let percent):
                batteryChipBody(eyebrow: "CHARGE", value: "\(percent)%", fraction: Double(percent) / 100, isLow: true)
            }
        }
    }

    @State private var lowBatteryPulse = false

    private func batteryChipBody(eyebrow: String, value: String, fraction: Double, isLow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(Theme.Fonts.eyebrow)
                .tracking(1.5)
                .foregroundStyle((isLow ? Color.white : Theme.Semantic.textSecondary).opacity(0.8))
            Text(value)
                .font(Theme.Fonts.batteryValue)
                .foregroundStyle(.white)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isLow ? Color.black.opacity(0.25) : Color.white.opacity(0.18))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isLow ? Color.white : Theme.Brand.orange)
                    .frame(width: max(0, min(1, fraction)) * 52)
            }
            .frame(width: 52, height: 4)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minWidth: 74, alignment: .leading)
        .background(
            isLow ? AnyShapeStyle(Theme.Brand.orange) : AnyShapeStyle(Theme.Semantic.glassFill),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(isLow ? Theme.Brand.orange : Theme.Semantic.glassStroke, lineWidth: 1)
        )
        .shadow(color: isLow ? Theme.Brand.orange.opacity(lowBatteryPulse ? 0.5 : 0) : .clear, radius: 11)
        .onAppear {
            guard isLow else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { lowBatteryPulse = true }
        }
    }

    // MARK: - Name block

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.deviceName.isEmpty ? "No headphones" : state.deviceName)
                .font(Theme.Fonts.deviceName)
                .tracking(-0.2)
                .foregroundStyle(Theme.Semantic.textPrimary)
            HStack(spacing: 7) {
                Circle()
                    .fill(Theme.Brand.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.Brand.orange.opacity(0.85), radius: 4)
                Text(content.subtitleText)
                    .font(Theme.Fonts.subText)
                    .foregroundStyle(Theme.Semantic.textSecondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(content.footerLeftText)
                .font(Theme.Fonts.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Theme.Semantic.textSecondary.opacity(0.8))
            Spacer(minLength: 0)
            Text(content.footerRightText)
                .font(Theme.Fonts.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Theme.Semantic.textSecondary.opacity(0.8))
        }
    }
}

// MARK: - Previews (design/DESIGN_GUIDE.md §4; design/reference/01, 02, 30-32)

#if DEBUG
/// Stand-in for the real mode-controls slot NotchView actually passes in — these previews are
/// ExpandedCard's own, decoupled from NotchView's private modeSegments/statusCaption, but still
/// need *something* visibly marking where that slot sits.
private struct PreviewModeControlsSlot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MODE CONTROLS SLOT")
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.4))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.white.opacity(0.3))
                .frame(height: 52)
                .overlay(Text("existing segmented control").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)))
        }
    }
}

@MainActor
private func previewState(connected: Bool = true, battery: Int? = 82, hasPhoto: Bool = true) -> HeadphoneState {
    let state = HeadphoneState()
    state.connection = connected ? .connected : .disconnected
    state.deviceName = connected ? "JBL Tune 770NC" : ""
    state.modelNumberText = connected && hasPhoto ? "770NC" : ""
    state.photoAssetNames = connected && hasPhoto ? HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White") : nil
    state.batteryPercent = battery
    return state
}

#Preview("Top - Dark") {
    ExpandedCard(state: previewState(), dock: .top, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Top - Light") {
    ExpandedCard(state: previewState(), dock: .top, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Bottom - Dark") {
    ExpandedCard(state: previewState(), dock: .bottom, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Bottom - Light") {
    ExpandedCard(state: previewState(), dock: .bottom, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Left - Dark") {
    ExpandedCard(state: previewState(), dock: .left, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Left - Light") {
    ExpandedCard(state: previewState(), dock: .left, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Right - Dark") {
    ExpandedCard(state: previewState(), dock: .right, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Right - Light") {
    ExpandedCard(state: previewState(), dock: .right, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Low Battery - Dark") {
    ExpandedCard(state: previewState(battery: 9), dock: .top, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Low Battery - Light") {
    ExpandedCard(state: previewState(battery: 9), dock: .top, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("No Device - Dark") {
    ExpandedCard(state: previewState(connected: false, battery: nil), dock: .top, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Unknown Model - Dark") {
    ExpandedCard(state: previewState(hasPhoto: false), dock: .top, onCollapseTapped: {}) { PreviewModeControlsSlot() }
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}
#endif
