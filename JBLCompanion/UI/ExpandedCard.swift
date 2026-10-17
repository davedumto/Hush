import SwiftUI

/// The expanded card — design/DESIGN_GUIDE.md §4 and §5 "Conditions". Only the top dock is
/// reachable from the live app today (NotchPanel has no left/right/bottom placement logic yet,
/// same limitation as CollapsedPill's own doc comment describes); bottom/left/right are fully
/// built and tested/previewed but not wired into real app state.
///
/// Internally resolves its own `CardCondition` (CardConditionResolver) from `state`, and branches
/// the top-row chip, hero, name block, bottom section (mode buttons / skeleton / reconnect
/// actions), and footer on it — there's no externally-injected "mode controls slot" anymore (that
/// generic-closure pattern existed only because mode buttons were explicitly out of scope for an
/// earlier stage; now that the whole card's condition handling lives here, keeping that slot
/// separate would just split one cohesive concern across two places).
struct ExpandedCard: View {
    let state: HeadphoneState
    let dock: CardDock
    let onCollapseTapped: () -> Void
    /// Per-mode "is this command frame hardware-verified" check (DeviceProfile.isModeVerified).
    let isModeVerified: (CommandableNoiseMode) -> Bool
    /// Whether the connected device's own model has noise control wired up at all
    /// (DeviceProfile.supportsNoiseControl).
    let supportsNoiseControl: Bool
    let onSelectNoiseMode: (CommandableNoiseMode) -> Void
    /// §5 "No headphones": re-runs classic detection and the RFCOMM open through the existing
    /// entry points — this view never touches Bluetooth itself.
    let onReconnectTapped: () -> Void
    let onOpenBluetoothSettingsTapped: () -> Void
    /// §5 "No headphones": "Last seen: <last matched profile display name>" — nil omits the line.
    /// Read from UserDefaults by the caller (AppDelegate persists it on every successful match);
    /// this view stays a pure function of its inputs, no UserDefaults access of its own.
    let lastMatchedProfileDisplayName: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVertical: Bool { dock.isVertical }
    // design/DESIGN_GUIDE.md §4: "Height follows content, about 470" — not exactly 470. Summing
    // every element (top row 28 + hero 236 + name block ~56 + mode buttons/status ~91 + footer
    // ~25, plus 28 of panel padding and 14 of outer frame padding) comes to ~478, already over a
    // flat 470 before accounting for any font-metric slack — that's real, measured overflow, not
    // a guess. 500 gives genuine headroom instead of a number that was never actually enough.
    private var cardSize: CGSize {
        isVertical ? CGSize(width: 296, height: 500) : CGSize(width: 374, height: 500)
    }
    private var heroHeight: CGFloat { isVertical ? 196 : 236 }
    private var photoHeight: CGFloat { isVertical ? 168 : 206 }
    private var modelNumberFontSize: CGFloat { isVertical ? 112 : 150 }
    private var tabLengthAlongEdge: CGFloat { isVertical ? 92 : 116 }
    // Floored at CutoutTabShape's outerCornerRadius (18): canonicalTopPath's straight wall
    // segment length is depthIntoPanel - outerCornerRadius, so going lower makes that segment
    // negative and breaks the fillet/corner geometry (the "overlapping circles" bug from before).
    // At 18, the wall length is exactly 0 — the fillet and outer corner meet directly, which is
    // the shallowest the tab can get without touching the guide's own radius tokens.
    private var tabDepthIntoPanel: CGFloat { 18 }

    /// §5: classicConnected/firstStatusEventReceived are both derived from existing HeadphoneState
    /// fields, not new raw state — CLAUDE.md/the task: "add a derived connecting state with no
    /// Bluetooth changes." `noiseMode` resets to `.unknown` on every disconnect (AppDelegate) and
    /// only ever becomes something else via a real RACE status event, so `!= .unknown` is exactly
    /// "at least one status event has arrived since connecting."
    private var condition: CardCondition {
        CardConditionResolver.resolve(
            classicConnected: state.connection == .connected,
            firstStatusEventReceived: state.noiseMode != .unknown,
            batteryPercent: state.batteryPercent,
            controlsAvailable: ModeButtonResolver.hasWorkingControls(
                supportsNoiseControl: supportsNoiseControl, isModeVerified: isModeVerified
            )
        )
    }
    private var isConnecting: Bool { condition == .connecting }
    private var isNoDevice: Bool { condition == .noDevice }

    /// Only meaningful for the "normal" conditions (controlsUnavailable/lowBattery/connected) —
    /// noDevice/connecting render their own name-block text directly.
    private var content: ExpandedCardContent {
        ExpandedCardContent.resolve(batteryPercent: state.batteryPercent)
    }

    var body: some View {
        ZStack {
            frame
            panelContent
            tab
        }
        .frame(width: cardSize.width, height: cardSize.height)
        // Without this, a click on any part of the card with no SwiftUI gesture of its own (the
        // frame fill, the panel gradient, empty hero space) falls straight through the hosting
        // view to the native NotchSilhouetteView underneath, whose own mouseDown/mouseUp treats
        // any click inside its shape as a tap-to-toggle — collapsing the card immediately, then
        // the still-hovering mouse re-triggers the hover-open timer, so it reopens right after.
        // This absorbs those clicks (doing nothing) so only the tab and the real buttons respond.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    // MARK: - Frame + panel

    private var frame: some View {
        RoundedRectangle(cornerRadius: 33, style: .continuous)
            .fill(Theme.Semantic.cardFrame)
            .shadow(
                color: colorScheme == .dark ? .clear : Theme.Brand.black.opacity(0.6),
                radius: 30, x: 0, y: 30
            )
            // The brand-accent edge: drawn here, not left to NotchSilhouetteView's own native
            // edgeLayer (which strokes the identical path underneath) — this card frame is fully
            // opaque and sits on top of it in z-order, so the native stroke stays mostly hidden
            // once real content is showing. Drawing it again here keeps it visible while open.
            .overlay(
                RoundedRectangle(cornerRadius: 33, style: .continuous)
                    .strokeBorder(Theme.Brand.orange.opacity(0.9), lineWidth: 1.5)
            )
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            heroSection
            nameBlock
                .padding(.top, 10)
            bottomSection
                .padding(.top, 12)
            footer
                .padding(.top, 12)
        }
        .padding(panelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelGradient, in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .padding(7)
        // §9.5 "Connecting to connected"/"Connected to disconnected": a plain crossfade across
        // whichever parts of the card just changed. The card's own height is fixed (cardSize,
        // regardless of condition — see NotchPanel's own doc comment on why that's deliberate),
        // so there's no height change left for the guide's "collapse spring" to actually animate.
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : .easeOut(duration: 0.3), value: condition)
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
        // Centers the mark (+wordmark) within the tab's own (shallow) depth — a modest fixed
        // inset reads correctly without per-dock measurement.
        switch dock {
        case .top: return EdgeInsets(top: 3, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: 3, trailing: 0)
        case .left: return EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0)
        case .right: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 4)
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
    /// HushMark's own flattened asset always renders its dot at full orange, which is fine for
    /// every caller except the no-device hero (§5: "dot dimmed"), hence `dotOpacity`.
    private func markGlyph(size: CGFloat, color: Color, dotOpacity: Double = 1) -> some View {
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
                .opacity(dotOpacity)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Top row

    private var topRow: some View {
        HStack(spacing: 8) {
            topRowChip
            Spacer(minLength: 0)
            iconButton("IconSettings")
            iconButton("IconPower")
        }
    }

    /// §5: the top-left chip itself swaps content for "No device" and "Connecting" — otherwise
    /// it's the normal model-number chip (empty/hidden when there's no model number to show).
    @ViewBuilder
    private var topRowChip: some View {
        switch condition {
        case .noDevice:
            chipCapsule {
                Text("No device")
                    .font(Theme.Fonts.modelChip)
                    .foregroundStyle(Theme.Semantic.chipInk)
            }
        case .connecting:
            chipCapsule {
                HStack(spacing: 6) {
                    ConnectingSpinner()
                    Text("Connecting")
                        .font(Theme.Fonts.modelChip)
                        .foregroundStyle(Theme.Semantic.chipInk)
                }
            }
        case .controlsUnavailable, .lowBattery, .connected:
            if !state.modelNumberText.isEmpty {
                chipCapsule {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.Brand.orange)
                            .frame(width: 7, height: 7)
                            .shadow(color: Theme.Brand.orange.opacity(0.85), radius: 4.5)
                        Text(state.modelNumberText)
                            .font(Theme.Fonts.modelChip)
                            .foregroundStyle(Theme.Semantic.chipInk)
                    }
                }
            }
        }
    }

    private func chipCapsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Theme.Semantic.chipFill, in: Capsule())
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
        // GeometryReader for the hero's own *actual* rendered width — §4's "22% from the left"
        // etc are percentages of the hero itself, not the outer card, and hand-computing that by
        // subtracting padding from cardSize (the previous approach) was only an approximation.
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                Color.clear

                // §4 hero layers, back to front. Present in every condition (including
                // no-device/connecting — §5's own reference images keep the ambient glow/floor
                // shadow behind the mark or the desaturated photo).
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
                        .position(x: geo.size.width / 2, y: heroHeight * 0.58)
                } else {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [Theme.Brand.black.opacity(0.45), Theme.Brand.black.opacity(0)],
                                center: .center, startRadius: 0, endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 26)
                        .position(x: geo.size.width / 2, y: heroHeight - 13)
                }

                modelNumberView
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.top, 4)

                // §4: "Centred, bottom aligned" — not leading-aligned.
                photoView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                // §5 "No headphones": no hotspot (nothing to tag on a mark with no real photo).
                if !isNoDevice {
                    hotspot
                        .position(x: geo.size.width * (isVertical ? 0.14 : 0.22), y: heroHeight * 0.62)
                }

                // §5: "no battery chip" while connecting or with no device, even if a BLE reading
                // happens to already be cached from a previous connection.
                if !isNoDevice && !isConnecting {
                    batteryChip
                        .padding(.bottom, isVertical ? 6 : 18)
                }
            }
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
            // Light theme's number is solid white (§8), unlike dark theme's own naturally-subtle
            // navy-on-navy gradient — without this, the edges exposed past the (also white, in
            // light theme) photo read as a flat competing blob rather than a layered watermark.
            .shadow(color: Theme.Brand.black.opacity(colorScheme == .dark ? 0 : 0.14), radius: 6, x: 0, y: 3)
            // §5 "Connecting": "model number at 35%". Empty (no-device, or nothing matched yet)
            // always wins regardless of condition — there's nothing to fade in at any opacity.
            .opacity(state.modelNumberText.isEmpty ? 0 : (isConnecting ? 0.35 : 1))
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
                // §5 "Connecting": "photo at 30% and fully desaturated".
                .opacity(isConnecting ? 0.3 : 1)
                .saturation(isConnecting ? 0 : 1)
        } else if isNoDevice {
            // §5 "No headphones": "HushMark at 118 (side docks 92), arch white 32%, dot dimmed".
            markGlyph(
                size: 118, color: colorScheme == .dark ? .white.opacity(0.32) : Theme.Brand.navy.opacity(0.32),
                dotOpacity: 0.5
            )
            .frame(height: photoHeight)
        } else {
            // CLAUDE.md / §4: unknown matched model (still connected) uses the HushMark, no photo.
            markGlyph(size: 118, color: colorScheme == .dark ? .white.opacity(0.32) : Theme.Brand.navy.opacity(0.32))
                .frame(height: photoHeight)
                .opacity(isConnecting ? 0.3 : 1)
                .saturation(isConnecting ? 0 : 1)
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
        // Low battery's chip is solid BrandOrange in both themes, so white ink always has plenty
        // of contrast there. The normal GlassFill chip is a different story: in light theme its
        // translucent-white fill sits over an already-brighter panel and reads pale, not dark, so
        // white text loses contrast against it — dark navy ink is what the chip actually needs
        // there, same reasoning as ChipInk for the model chip.
        let valueColor: Color = isLow ? .white : (colorScheme == .dark ? .white : Theme.Brand.navy)
        let eyebrowColor: Color = isLow ? .white.opacity(0.85) : (colorScheme == .dark ? Theme.Semantic.textSecondary.opacity(0.8) : Theme.Brand.navy.opacity(0.6))

        return VStack(alignment: .leading, spacing: 3) {
            Text(eyebrow)
                .font(Theme.Fonts.eyebrow)
                .tracking(1.5)
                .foregroundStyle(eyebrowColor)
            Text(value)
                .font(Theme.Fonts.batteryValue)
                .contentTransition(.numericText())
                .foregroundStyle(valueColor)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isLow ? Color.black.opacity(0.25) : (colorScheme == .dark ? Color.white.opacity(0.18) : Theme.Brand.navy.opacity(0.18)))
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isLow ? Color.white : Theme.Brand.orange)
                    .frame(width: max(0, min(1, fraction)) * 52)
                    // §9.5 "Battery value": "bar width animates 300 ms ease out".
                    .animation(reduceMotion ? .easeInOut(duration: 0.16) : .easeOut(duration: 0.3), value: fraction)
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
                // Light theme specifically: an orange edge separates the chip from the hero number
                // sitting behind/near it, which is also light/white there (same "white-on-white"
                // issue the number's own drop shadow addresses for the photo).
                .strokeBorder(isLow || colorScheme == .light ? Theme.Brand.orange : Theme.Semantic.glassStroke, lineWidth: 1)
        )
        // §9.5 "Battery crossing 15%": "Chip color crossfades to orange over 250 ms, then the
        // pulse starts" — the fill/border/ink swaps above are already driven by `isLow`, so a
        // single animation binding on it crossfades the whole chip together.
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : .easeInOut(duration: 0.25), value: isLow)
        .shadow(color: isLow ? Theme.Brand.orange.opacity(lowBatteryPulse ? 0.5 : 0) : .clear, radius: 11)
        .onAppear {
            guard isLow, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { lowBatteryPulse = true }
        }
    }

    // MARK: - Name block

    @ViewBuilder
    private var nameBlock: some View {
        switch condition {
        case .noDevice:
            VStack(alignment: .leading, spacing: 4) {
                Text("No headphones")
                    .font(Theme.Fonts.deviceName)
                    .tracking(-0.2)
                    .foregroundStyle(Theme.Semantic.textPrimary)
                // §5: "grey dot" here, not the usual orange one — and the whole line is omitted
                // when nothing has ever matched.
                if let lastSeen = CardConditionResolver.lastSeenText(lastMatchedProfileDisplayName: lastMatchedProfileDisplayName) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 7, height: 7)
                        Text(lastSeen)
                            .font(Theme.Fonts.subText)
                            .foregroundStyle(Theme.Semantic.textSecondary)
                    }
                }
            }
        case .connecting:
            VStack(alignment: .leading, spacing: 4) {
                Text(state.deviceName)
                    .font(Theme.Fonts.deviceName)
                    .tracking(-0.2)
                    .foregroundStyle(Theme.Semantic.textPrimary)
                HStack(spacing: 7) {
                    ConnectingPulsingDot()
                    Text("Connecting…")
                        .font(Theme.Fonts.subText)
                        .foregroundStyle(Theme.Semantic.textSecondary)
                }
            }
        case .controlsUnavailable, .lowBattery, .connected:
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
    }

    // MARK: - Bottom section (mode buttons / connecting skeleton / no-device actions)

    @ViewBuilder
    private var bottomSection: some View {
        switch condition {
        case .noDevice:
            NoHeadphonesActions(
                dock: dock, onReconnectTapped: onReconnectTapped,
                onOpenBluetoothSettingsTapped: onOpenBluetoothSettingsTapped
            )
        case .connecting:
            ConnectingPlaceholder(dock: dock)
        case .controlsUnavailable, .lowBattery, .connected:
            ModeButtonsSection(
                state: state, dock: dock, isModeVerified: isModeVerified,
                supportsNoiseControl: supportsNoiseControl, onSelectNoiseMode: onSelectNoiseMode
            )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(CardConditionResolver.footerLeftText(for: condition))
                .font(Theme.Fonts.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Theme.Semantic.textSecondary.opacity(0.8))
            Spacer(minLength: 0)
            Text(CardConditionResolver.footerRightText(for: condition))
                .font(Theme.Fonts.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Theme.Semantic.textSecondary.opacity(0.8))
        }
    }
}

// MARK: - Previews (design/DESIGN_GUIDE.md §4/§5; design/reference/01, 02, 19-21, 27-29, 30-32)

#if DEBUG
@MainActor
private func previewState(
    connected: Bool = true, battery: Int? = 82, hasPhoto: Bool = true,
    noiseMode: NoiseMode = .anc, modelNumber: String = "770NC", deviceName: String = "JBL Tune 770NC"
) -> HeadphoneState {
    let state = HeadphoneState()
    state.connection = connected ? .connected : .disconnected
    state.deviceName = connected ? deviceName : ""
    state.modelNumberText = connected && hasPhoto ? modelNumber : ""
    state.photoAssetNames = connected && hasPhoto ? HeadphonePhotoAssetNames(black: "Tune\(modelNumber.prefix(3))Black", white: "Tune\(modelNumber.prefix(3))White") : nil
    state.batteryPercent = connected ? battery : nil
    state.noiseMode = connected ? noiseMode : .unknown
    return state
}

private let previewVerified: (CommandableNoiseMode) -> Bool = { $0 != .off }
private let previewUnverified: (CommandableNoiseMode) -> Bool = { _ in false }

private func previewCard(
    _ state: HeadphoneState, _ dock: CardDock,
    isModeVerified: @escaping (CommandableNoiseMode) -> Bool = previewVerified,
    supportsNoiseControl: Bool = true, lastSeen: String? = "JBL Tune 770NC"
) -> some View {
    ExpandedCard(
        state: state, dock: dock, onCollapseTapped: {}, isModeVerified: isModeVerified,
        supportsNoiseControl: supportsNoiseControl, onSelectNoiseMode: { _ in }, onReconnectTapped: {},
        onOpenBluetoothSettingsTapped: {}, lastMatchedProfileDisplayName: lastSeen
    )
}

#Preview("Top - Dark") {
    previewCard(previewState(), .top).padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Top - Light") {
    previewCard(previewState(), .top).padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Bottom - Dark") {
    previewCard(previewState(), .bottom).padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Bottom - Light") {
    previewCard(previewState(), .bottom).padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Left - Dark") {
    previewCard(previewState(), .left).padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Left - Light") {
    previewCard(previewState(), .left).padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Right - Dark") {
    previewCard(previewState(), .right).padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Right - Light") {
    previewCard(previewState(), .right).padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Low Battery - Dark") {
    previewCard(previewState(battery: 9), .top).padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Low Battery - Light") {
    previewCard(previewState(battery: 9), .top).padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Unknown Model - Dark") {
    previewCard(previewState(hasPhoto: false), .top).padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Connecting - Dark") {
    previewCard(previewState(noiseMode: .unknown), .top).padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Connecting - Light") {
    previewCard(previewState(noiseMode: .unknown), .top).padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("No Headphones - Dark") {
    previewCard(previewState(connected: false, battery: nil), .top)
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("No Headphones - Light") {
    previewCard(previewState(connected: false, battery: nil), .top)
        .padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("No Headphones - Never Matched - Dark") {
    previewCard(previewState(connected: false, battery: nil), .top, lastSeen: nil)
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("No Headphones - Side Dock - Dark") {
    previewCard(previewState(connected: false, battery: nil), .left)
        .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("No Headphones - Side Dock - Light") {
    previewCard(previewState(connected: false, battery: nil), .left)
        .padding(40).background(Color.white).preferredColorScheme(.light)
}

#Preview("Controls Unavailable (670NC) - Dark") {
    previewCard(
        previewState(battery: 64, noiseMode: .anc, modelNumber: "670NC", deviceName: "JBL Tune 670NC"),
        .top, isModeVerified: previewUnverified, supportsNoiseControl: false
    )
    .padding(40).background(Color.black).preferredColorScheme(.dark)
}

#Preview("Controls Unavailable (670NC) - Light") {
    previewCard(
        previewState(battery: 64, noiseMode: .anc, modelNumber: "670NC", deviceName: "JBL Tune 670NC"),
        .top, isModeVerified: previewUnverified, supportsNoiseControl: false
    )
    .padding(40).background(Color.white).preferredColorScheme(.light)
}
#endif
