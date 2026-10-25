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
    /// Non-nil only when docked flush into a screen corner (NotchPanel.dockedCorner's own doc
    /// comment) — shifts the tab (below) from the edge's own middle toward that corner instead,
    /// so it visually sits exactly where the collapsed island was, giving the illusion that
    /// opening/closing the tray never moves it (owner request).
    var dockedCorner: ScreenCorner? = nil
    /// Free-floating only (NotchPanel.freeFloatingNotch()'s own doc comment) — which edge of the
    /// card the cut-out notch sits on and how far along it, so it stays aligned with the island
    /// instead of centered on `dock`'s own edge (which, for a free-floating card, isn't a real
    /// screen edge the card is flush against at all — owner spec, 2026-10-21: the tray opens
    /// adjacent to the island in whichever direction its grid region names). `nil` for every
    /// other placement mode, which keep the plain, centered `CutoutTabShape` untouched.
    var freeFloatingNotch: (dock: CardDock, offset: CGFloat, anchor: UnitPoint)? = nil
    /// Owner spec, 2026-10-25: "remove the notch inside the tray for just this one that is
    /// happening from the notch" — on a real physical camera notch, `tab`'s own `CutoutTabShape`
    /// (a drawn, fake notch-shaped bump) is now redundant: the real notch plus NotchExtensionBar's
    /// fused wings already give the card its visual anchor, so drawing a second, decorative fake
    /// one on top of it read as a notch inside the notch. `true` only for a real top-edge camera
    /// notch (never free-floating/corner-docked, which already have their own `tab` variants) —
    /// still keeps a same-sized invisible tap target in the tab's usual spot so collapsing by
    /// clicking there still works, just with nothing drawn.
    var isAttachedToRealNotch: Bool = false
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
    /// §9.1 point 5 "Photo flight": shared with CollapsedPill's own photo image by NotchView, the
    /// common ancestor that owns the `@Namespace`. `nil` for every preview/caller that doesn't
    /// need the flight (most of them — matchedGeometryEffect only does anything useful when both
    /// the pill and the card are mounted in the same transition, which only NotchView arranges).
    var photoNamespace: Namespace.ID? = nil
    /// Hardware-verified 2026-10-22 (DeviceProfile.powerOffCommandFrame's own doc comment) —
    /// same reasoning as onSelectNoiseMode: AppDelegate owns the real send/WriteGuard/rate-limit
    /// path, this view only calls it.
    var onPowerOff: () -> Void = {}
    /// DeviceProfile.isPowerOffVerified — gates `tab`'s IconPower button the same way
    /// isModeVerified gates each mode button: unverified means disabled, not hidden, so the
    /// control's presence doesn't silently change per model.
    var canPowerOff: Bool = false
    /// DeviceProfile.isEqualizerVerified's own doc comment — gates the equalizer row in the
    /// settings picker sheet and the curve/grid inside EqualizerControls itself.
    var canUseEqualizer: Bool = false
    var onSelectEqualizerPreset: (EqualizerPreset) -> Void = { _ in }
    var onSetEqualizerOn: (Bool) -> Void = { _ in }
    /// Pushed back through to IslandSettingsControls — AppDelegate.notchSettingsDidChange(), same
    /// callback Island Settings already triggers on every change.
    var onIslandSettingsChanged: () -> Void = {}
    var hasRealNotchOnCurrentDisplay: () -> Bool = { false }
    var currentDisplayUUID: () -> String? = { nil }
    /// DeviceToggle.maxVolumeLimiter/.voicePrompt's own doc comments — gates each row in the
    /// Headphone Settings sheet independently (neither gates the other).
    var canUseMaxVolumeLimiter: Bool = false
    var onSetMaxVolumeLimiter: (Bool) -> Void = { _ in }
    var canUseVoicePrompt: Bool = false
    var onSetVoicePrompt: (Bool) -> Void = { _ in }
    /// Bumped by NotchPanel.requestOpenIslandSettings() (the fallback NSStatusItem menu's own
    /// "Island Settings…" item — NotchUIState.islandSettingsRequestToken's own doc comment) —
    /// jumps straight to the in-tray Island Settings sheet, skipping the picker, since that's the
    /// one sheet the menu item is asking for specifically.
    var openIslandSettingsRequestToken: Int = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the "Turn off headphones?" confirm/cancel alert (owner request, matching the real
    /// JBL app's own confirmation popup — the capture that found this frame in the first place).
    @State private var showingPowerOffConfirm = false
    /// One gear icon opens a small picker (Island Settings / Equalizer); each opens its own
    /// in-tray sheet from there (owner request, 2026-10-22: "I do not want to be opening all
    /// those windows" — both used to be separate Windows). Mirrors `showingPowerOffConfirm`'s own
    /// slide-up-sheet pattern, just with one more level: picker -> destination.
    @State private var activeTraySheet: TraySheet? = nil

    private enum TraySheet: Hashable {
        case settingsPicker
        case islandSettings
        case equalizer
        case headphoneSettings

        var isRoot: Bool { self == .settingsPicker }

        var title: String? {
            switch self {
            case .settingsPicker: return nil
            case .islandSettings: return "Island Settings"
            case .equalizer: return "Equalizer"
            case .headphoneSettings: return "Headphone Settings"
            }
        }
    }

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
    private var photoHeight: CGFloat { isVertical ? 158 : 192 }
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
            if showingPowerOffConfirm {
                powerOffConfirmSheet
            }
            traySheetOverlay
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
        .onChange(of: openIslandSettingsRequestToken) { _, newValue in
            guard newValue > 0 else { return }
            withAnimation(powerOffSheetAnimation) { activeTraySheet = .islandSettings }
        }
    }

    // MARK: - Frame + panel

    private var frame: some View {
        // design/DESIGN_GUIDE.md §4 "Frame and panel": CardFrame fill, corner radius 33, no
        // border. An orange border was added here on owner request earlier, then explicitly
        // removed again on owner request after a closer design review — CLAUDE.md's deviations
        // list is updated to match; this is the second and (per that review) final word on it.
        RoundedRectangle(cornerRadius: 33, style: .continuous)
            .fill(Theme.Semantic.cardFrame)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
                .padding(cornerTabTopRowClearance)
                .modifier(StaggerIn(block: .topRow))
            heroSection
                .modifier(StaggerIn(block: .hero))
            nameBlock
                .padding(.top, 10)
                .modifier(StaggerIn(block: .name))
            bottomSection
                .padding(.top, 12)
                .modifier(StaggerIn(block: .controls))
            footer
                .padding(.top, 12)
                .padding(cornerTabFooterClearance)
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

    /// Extra inset on just the footer row — the one closest to a *bottom*-corner tab (`cornerTab`,
    /// which sits off to one side near the actual corner, not centered the way the normal tab is)
    /// — clearing only the specific content it would otherwise overlap, rather than padding the
    /// whole panel (which visibly shrank/distorted the rest of the card's own layout for no
    /// reason, since nothing else in it actually sits near that corner).
    private var cornerTabFooterClearance: EdgeInsets {
        guard dock == .bottom else { return EdgeInsets() }
        return cornerTabRowClearance
    }

    /// `cornerTabFooterClearance`'s own counterpart for the top row, for a *top*-corner tab.
    private var cornerTabTopRowClearance: EdgeInsets {
        guard dock == .top else { return EdgeInsets() }
        return cornerTabRowClearance
    }

    private var cornerTabRowClearance: EdgeInsets {
        // Clears the corner tab's own diameter (DockPlacement.collapsedPillDiameter, 52) plus its
        // inset from the edge (cornerTabPosition's own `alongEdgeInset`) with a little to spare.
        let clearance: CGFloat = 50
        switch dockedCorner {
        case .topLeft, .bottomLeft: return EdgeInsets(top: 0, leading: clearance, bottom: 0, trailing: 0)
        case .topRight, .bottomRight: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: clearance)
        case nil: return EdgeInsets()
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
        if isAttachedToRealNotch {
            invisibleNotchTapTarget
        } else if dockedCorner != nil {
            cornerTab
        } else {
            // A free-floating notch can land on any of the 4 card edges regardless of the card's
            // own base shape (`dock`/`isVertical`, which for free-floating always stays whichever
            // orientation `effectiveEdgeForGeometry` picked — NotchPanel's own doc comment) — e.g.
            // a landscape card can still have its notch on a `.left`/`.right` edge. `lengthAlongEdge`
            // has to match *that* edge's own orientation, not the card's.
            let tabDock = freeFloatingNotch?.dock ?? dock
            let tabOffset = freeFloatingNotch?.offset ?? 0
            let length: CGFloat = tabDock.isVertical ? 92 : 116
            let shape = CutoutTabShape(dock: tabDock, lengthAlongEdge: length, depthIntoPanel: tabDepthIntoPanel, offset: tabOffset)
            // `.overlay(alignment:)` below positions its content relative to the *whole card*,
            // with no idea the shape itself just slid by `tabOffset` (`CutoutTabShape.offset`'s
            // own doc comment) — for `tabOffset == 0` (every docked case, always) that's
            // invisible, since the shape's own centered position and the card's own center
            // coincide anyway. The moment the notch actually slides, the icon stayed put while the
            // shape slid out from under it — a real regression, caught on a live screenshot
            // (regions 1/3/7/9, where the notch offset is largest). Shifting the overlay content
            // by that same `tabOffset`, on the same axis the shape itself moved along, is what
            // keeps the icon riding along with the shape instead of staying fixed to the card.
            let contentOffset: CGSize = tabDock.isVertical ? CGSize(width: 0, height: tabOffset) : CGSize(width: tabOffset, height: 0)
            shape
                .fill(Theme.Semantic.cardFrame)
                .overlay(alignment: ExpandedCard.tabContentAlignment(for: tabDock)) {
                    tabContent
                        .padding(ExpandedCard.tabContentPadding(for: tabDock))
                        .offset(contentOffset)
                }
                .frame(width: cardSize.width, height: cardSize.height)
                .contentShape(shape)
                .onTapGesture { onCollapseTapped() }
        }
    }

    /// `isAttachedToRealNotch`'s own doc comment: no `CutoutTabShape` drawn here on purpose — the
    /// real physical notch plus NotchExtensionBar's fused wings already anchor the card visually,
    /// so there's nothing left to draw, just the same tap-to-collapse hit target the shape used to
    /// carry, centered the same way the plain (non-corner, non-free) tab always was.
    private var invisibleNotchTapTarget: some View {
        Color.clear
            .frame(width: 116, height: tabDepthIntoPanel)
            .contentShape(Rectangle())
            .frame(width: cardSize.width, height: cardSize.height, alignment: .top)
            .onTapGesture { onCollapseTapped() }
    }

    /// The corner-docked tab: a plain circle — the same silhouette the collapsed island itself
    /// always has (CollapsedPill's own doc comment) — sitting flush against the card's docked
    /// edge, slid along it toward `dockedCorner`, rather than `CutoutTabShape`'s elongated,
    /// filleted rectangle. Owner request: "circular looking notch," matching the collapsed
    /// island's own look so the tray reads as a direct continuation of it, not a different shape.
    @ViewBuilder
    private var cornerTab: some View {
        let diameter = DockPlacement.collapsedPillDiameter
        Circle()
            .fill(Theme.Semantic.cardFrame)
            .frame(width: diameter, height: diameter)
            .overlay { tabGlyph(size: 20) }
            .contentShape(Circle())
            .position(cornerTabPosition)
            .frame(width: cardSize.width, height: cardSize.height)
            .onTapGesture { onCollapseTapped() }
    }

    /// Touching the card's own docked edge (`dock` — already resolved to the correct top/bottom
    /// half for every corner, not just the bottom two — NotchPanel.effectiveEdgeForGeometry's own
    /// doc comment) from the *inside* — flush against it, but never crossing it (owner: "nothing
    /// should leave the tray" — straddling the edge, half poking outside the card, was wrong).
    /// Slid along that edge toward `dockedCorner`, not jammed into the literal corner point itself
    /// — matching the owner's own reference image, which shows the notch sitting at the edge near
    /// the corner, not exactly on it.
    private var cornerTabPosition: CGPoint {
        let diameter = DockPlacement.collapsedPillDiameter
        let y: CGFloat = dock == .top ? diameter / 2 : cardSize.height - diameter / 2
        let alongEdgeInset = diameter / 2 + 4
        let x: CGFloat
        switch dockedCorner {
        case .topLeft, .bottomLeft: x = alongEdgeInset
        case .topRight, .bottomRight: x = cardSize.width - alongEdgeInset
        case nil: x = cardSize.width / 2
        }
        return CGPoint(x: x, y: y)
    }

    /// Static, parameterized by `dock` rather than reading the instance's own `dock` property
    /// directly — `tab`'s own doc comment on why: a free-floating card's notch edge can differ
    /// from the card's base `dock`, so both call sites have to be able to ask for *either* one.
    private static func tabContentAlignment(for dock: CardDock) -> Alignment {
        switch dock {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private static func tabContentPadding(for dock: CardDock) -> EdgeInsets {
        // Centers the mark (+wordmark) within the tab's own (shallow) depth — a modest fixed
        // inset reads correctly without per-dock measurement.
        switch dock {
        case .top: return EdgeInsets(top: 3, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets(top: 0, leading: 0, bottom: 3, trailing: 0)
        case .left: return EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0)
        case .right: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 4)
        }
    }

    // Just the mark, on every dock — owner request: no "hush." wordmark on the tab at all anymore
    // (top/bottom used to show it alongside the mark; §4's own "HushMark 20 only" was already the
    // rule for side docks, now applied uniformly instead of only there).
    private var tabContent: some View {
        tabGlyph(size: 20)
    }

    /// Owner spec, 2026-10-25: "when media is playing, the logo icon when the tray is open should
    /// have that waveform vibe too" — the tab/corner-tab's own brand mark swaps to the same shared
    /// `AnimatedWaveformBars` CollapsedPill and NotchExtensionBar already use, same as
    /// CollapsedPill.primaryVisual's own swap. Both tab call sites (`cornerTab`, `tabContent`) route
    /// through here so neither one can drift out of sync with the other.
    @ViewBuilder
    private func tabGlyph(size: CGFloat) -> some View {
        let color = colorScheme == .dark ? Color.white : Theme.Brand.navy
        if state.isMediaPlaying {
            AnimatedWaveformBars(height: size, tint: color)
        } else {
            markGlyph(size: size, color: color)
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
            iconButton("IconSettings", onTap: openSettingsPicker)
            iconButton(
                "IconPower", tint: canPowerOff ? .white : .white.opacity(0.3),
                onTap: canPowerOff ? { withAnimation(powerOffSheetAnimation) { showingPowerOffConfirm = true } } : nil
            )
        }
    }

    /// Single entry point for both Island Settings and Equalizer now (owner request, 2026-10-22:
    /// "use the settings icon instead so it does not clash with the icon of the equalizer" —
    /// resolved by removing the second icon entirely and routing both through one gear-triggered
    /// picker sheet, same `.move(edge: .bottom)` pattern as `powerOffConfirmSheet`).
    private func openSettingsPicker() {
        withAnimation(powerOffSheetAnimation) { activeTraySheet = .settingsPicker }
    }

    /// A card-native confirm/cancel sheet (owner request), not a system `.alert` — matches the
    /// app's own styling and the real JBL app's own confirmation popup (the capture that found
    /// this frame in the first place). Stays entirely within the tray's own bounds (owner
    /// request): clipped to the card's own rounded rect, not a separate screen-wide window, so it
    /// never conflicts with "the panel must never steal focus."
    private var powerOffConfirmSheet: some View {
        ZStack(alignment: .bottom) {
            // "Blur the other parts faintly" — a real Material blur (not just a dim overlay),
            // kept faint via low opacity so the card's own content is still legible through it.
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
                .contentShape(Rectangle())
                .transition(.opacity)
                .onTapGesture { dismissPowerOffSheet() }

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button(action: dismissPowerOffSheet) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.Semantic.textSecondary)
                            .frame(width: 22, height: 22)
                            .background(Theme.Semantic.glassFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(spacing: 6) {
                    Text("Turn off headphones?")
                        .font(.custom("Fredoka-SemiBold", size: 17))
                        .foregroundStyle(Theme.Semantic.textPrimary)
                    Text("This will power off \(state.deviceName.isEmpty ? "the headphones" : state.deviceName) remotely.")
                        .font(Theme.Fonts.subText)
                        .foregroundStyle(Theme.Semantic.textSecondary)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    powerOffSheetButton("Cancel", textColor: Theme.Semantic.textPrimary, action: dismissPowerOffSheet)
                    powerOffSheetButton("Turn Off", textColor: .red) {
                        dismissPowerOffSheet()
                        onPowerOff()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(
                panelGradient,
                in: UnevenRoundedRectangle(topLeadingRadius: 27, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 27, style: .continuous)
            )
            .overlay(
                UnevenRoundedRectangle(topLeadingRadius: 27, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 27, style: .continuous)
                    .strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1)
            )
            // One transition on the whole sheet (not split across inner/outer layers, which fades
            // instead of visibly sliding — owner-reported) so open and close both genuinely slide
            // from the bottom edge, not just cross-fade.
            .transition(.move(edge: .bottom))
        }
        .clipShape(RoundedRectangle(cornerRadius: 33, style: .continuous))
    }

    private func dismissPowerOffSheet() {
        withAnimation(powerOffSheetAnimation) { showingPowerOffConfirm = false }
    }

    private var powerOffSheetAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private func powerOffSheetButton(_ title: String, textColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.statusModeName)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.Semantic.glassFill, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// A single persistent sheet container (scrim + bottom panel) that only slides up/down on
    /// open/close (`.move(edge: .bottom)`, nil <-> non-nil) — navigating *within* it (picker ->
    /// destination, back) swaps `traySheetBody` instead, keyed by `.id(activeTraySheet)` so it
    /// gets its own insert/remove diffing and genuinely animates (an `if let` alone only re-renders
    /// in place across two non-nil values — no transition fires — which is why the owner-reported
    /// "animation isn't active" bug was real: the picker's own open/close slid fine, but stepping
    /// into Island Settings/Equalizer from it was a silent snap). Each destination slides in from
    /// the trailing edge, like a push; the picker (root) slides in from leading, like a pop — a
    /// directional "push navigation" read instead of a flat crossfade.
    private var traySheetOverlay: some View {
        ZStack(alignment: .bottom) {
            if activeTraySheet != nil {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.9)
                    .contentShape(Rectangle())
                    .transition(.opacity)
                    .onTapGesture { dismissTraySheet() }

                VStack(alignment: .leading, spacing: 14) {
                    traySheetHeader
                    traySheetBody
                        .id(activeTraySheet)
                        .transition(.move(edge: (activeTraySheet?.isRoot ?? true) ? .leading : .trailing).combined(with: .opacity))
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
                .background(
                    panelGradient,
                    in: UnevenRoundedRectangle(topLeadingRadius: 27, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 27, style: .continuous)
                )
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 27, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 27, style: .continuous)
                        .strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1)
                )
                .clipped()
                .transition(.move(edge: .bottom))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 33, style: .continuous))
        // Owner-reported: open -> close -> tapping the gear again didn't reopen it. This ZStack
        // always exists in the card's own view tree now (it's not wrapped in an outer `if` the way
        // `powerOffConfirmSheet` is — that's what lets `traySheetBody`'s own `.id(activeTraySheet)`
        // survive picker<->destination navigation); with `activeTraySheet == nil` its own `if`
        // renders no children, but an empty ZStack can still claim hit-testing space over
        // whatever's behind it (here, the gear icon in `topRow`) for the remainder of a still-
        // settling SwiftUI transaction. This makes that explicit instead of relying on "empty means
        // untappable," which isn't actually guaranteed.
        .allowsHitTesting(activeTraySheet != nil)
    }

    @ViewBuilder
    private var traySheetHeader: some View {
        HStack(spacing: 10) {
            if let activeTraySheet, !activeTraySheet.isRoot {
                Button {
                    withAnimation(powerOffSheetAnimation) { self.activeTraySheet = .settingsPicker }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Semantic.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(Theme.Semantic.glassFill, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if let title = activeTraySheet?.title {
                Text(title)
                    .font(.custom("Fredoka-SemiBold", size: 17))
                    .foregroundStyle(Theme.Semantic.textPrimary)
            }
            Spacer()
            Button(action: dismissTraySheet) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Semantic.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Theme.Semantic.glassFill, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var traySheetBody: some View {
        switch activeTraySheet {
        case .settingsPicker, nil:
            VStack(spacing: 10) {
                traySheetPickerRow(title: "Island Settings", systemImage: "slider.horizontal.3") {
                    withAnimation(powerOffSheetAnimation) { activeTraySheet = .islandSettings }
                }
                traySheetPickerRow(title: "Equalizer", systemImage: "waveform") {
                    withAnimation(powerOffSheetAnimation) { activeTraySheet = .equalizer }
                }
                traySheetPickerRow(title: "Headphone Settings", systemImage: "gearshape.2") {
                    withAnimation(powerOffSheetAnimation) { activeTraySheet = .headphoneSettings }
                }
            }
        case .islandSettings:
            IslandSettingsControls(
                onSettingsChanged: onIslandSettingsChanged,
                hasRealNotchOnCurrentDisplay: hasRealNotchOnCurrentDisplay(), currentDisplayUUID: currentDisplayUUID()
            )
        case .equalizer:
            EqualizerControls(
                canUseEqualizer: canUseEqualizer, equalizerPreset: state.equalizerPreset, equalizerOn: state.equalizerOn,
                onSelectPreset: onSelectEqualizerPreset, onSetOn: onSetEqualizerOn
            )
        case .headphoneSettings:
            HeadphoneSettingsControls(
                canUseMaxVolumeLimiter: canUseMaxVolumeLimiter, maxVolumeLimiterOn: state.maxVolumeLimiterOn, onSetMaxVolumeLimiter: onSetMaxVolumeLimiter,
                canUseVoicePrompt: canUseVoicePrompt, voicePromptOn: state.voicePromptOn, onSetVoicePrompt: onSetVoicePrompt
            )
        }
    }

    private func dismissTraySheet() {
        withAnimation(powerOffSheetAnimation) { activeTraySheet = nil }
    }

    /// Orange icon badge (owner-reported: "you did not make use of orange too") instead of a bare
    /// orange glyph on glass — matches the accent-chip language the rest of the card already uses
    /// (the hero's own orange hotspot dot/glow). Each row gets its own rounded rect and stroke
    /// (not one joined glassRow block) so the two choices read as distinct tappable cards.
    private func traySheetPickerRow(title: String, systemImage: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.Brand.orange, in: Circle())
                Text(title)
                    .font(Theme.Fonts.subText)
                    .foregroundStyle(Theme.Semantic.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Semantic.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.Semantic.glassFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func iconButton(_ assetName: String, tint: Color = .white, onTap: (() -> Void)? = nil) -> some View {
        Circle()
            .strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1)
            .frame(width: 28, height: 28)
            .overlay(
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(tint)
            )
            .contentShape(Circle())
            .onTapGesture { onTap?() }
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

                // SwiftUI's Text frame top is the font ascender, not the glyph top — Fredoka-Bold's
                // own digits sit 0.273 x font size below it (ascender 974, cap height 701,
                // units-per-em 1000). Target is the digit top 6pt below the hero top (9pt side
                // docks): offset = 6 - 0.273*168 = -40 (top/bottom docks), 9 - 0.273*124 = -25 (side).
                modelNumberView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .offset(y: isVertical ? -25 : -40)

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

    /// Sized/tracked/gradient-stopped precisely for Fredoka-Bold's own metrics (ascender 974, cap
    /// height 701, units-per-em 1000) so the digits land exactly 6pt (side docks 9pt) below the
    /// hero top — see the `.offset` on this view's own placement in `heroSection` for the rest of
    /// that math. Previous version sank toward the hero's bottom-trailing-aligned ZStack with only
    /// a bare `.frame(maxWidth: .infinity)` and no vertical anchor of its own, landing almost
    /// entirely behind the photo instead of peeking out above it — not a hidden/masked/zero-opacity
    /// bug, a geometry one.
    private var modelNumberView: some View {
        let size: CGFloat = isVertical ? 124 : 168
        return Text(ExpandedCardContent.heroNumberText(from: state.modelNumberText))
            .font(.custom("Fredoka-Bold", size: size))
            .tracking(isVertical ? -1.2 : -1.7)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(modelNumberGradient)
            // §5 "Connecting": "model number at 35%". Empty (no-device, or nothing matched yet)
            // always wins regardless of condition — there's nothing to fade in at any opacity.
            .opacity(state.modelNumberText.isEmpty ? 0 : (isConnecting ? 0.35 : 1))
            .allowsHitTesting(false)
    }

    /// Fades the digits out toward the hero's own interior (not a flat two-stop gradient) so the
    /// part that peeks out above the photo reads as a genuine watermark, not a hard-edged shape
    /// competing with it. Stop locations are tuned against a Text frame height of 1.21x the font
    /// size (ascender + descender, line gap 0) — Fredoka-Bold's own metrics.
    private var modelNumberGradient: LinearGradient {
        let stops: [Gradient.Stop] = colorScheme == .dark
            ? [
                .init(color: Color(red: 0.227, green: 0.435, blue: 0.682), location: 0.09), // #3A6FAE
                .init(color: Color(red: 0.165, green: 0.337, blue: 0.533), location: 0.42), // #2A5688
                .init(color: Theme.Brand.navy.opacity(0), location: 0.77),
            ]
            : [
                .init(color: .white, location: 0.09),
                .init(color: .white, location: 0.385),
                .init(color: .white.opacity(0.22), location: 0.67),
                .init(color: .white.opacity(0), location: 0.83),
            ]
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder
    private var photoView: some View {
        if let assetName = currentPhotoAssetName {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: photoHeight)
                .shadow(
                    color: colorScheme == .dark ? Theme.Brand.black.opacity(0.55) : .clear,
                    radius: 13, x: 0, y: 22
                )
                // Light theme: a tight, almost-unblurred shadow first (the edge that actually
                // separates the white headphones from the white model number behind them — a
                // soft 13pt blur alone wasn't enough contrast right at the silhouette's own
                // boundary), then the normal soft drop shadow. Order matters: SwiftUI stacks
                // multiple `.shadow` modifiers in the order applied, each rendered under the
                // previous, so the tight edge-defining one has to be applied first.
                .shadow(color: colorScheme == .dark ? .clear : Theme.Brand.deepNavy.opacity(0.55), radius: 0.5, x: 0, y: 0)
                .shadow(color: colorScheme == .dark ? .clear : Theme.Brand.deepNavy.opacity(0.6), radius: 13, x: 0, y: 18)
                // §5 "Connecting": "photo at 30% and fully desaturated".
                .opacity(isConnecting ? 0.3 : 1)
                .saturation(isConnecting ? 0 : 1)
                // §9.1 point 5: the small pill photo flies and grows into this hero photo, sharing
                // this id/namespace with CollapsedPill's own photo image — skipped under Reduce
                // Motion (§9.6: "No photo flight"), where the two photos just crossfade in place.
                .modifier(PhotoFlight(namespace: reduceMotion ? nil : photoNamespace))
        } else if isNoDevice {
            // §5 "No headphones": "HushMark at 118 (side docks 92), arch white 32%, dot dimmed" —
            // reference 20/28 reads the dot about as faint as the arch itself, not half-strength;
            // 0.5 still looked like a clearly lit, solid-orange dot next to it.
            markGlyph(
                size: 118, color: colorScheme == .dark ? .white.opacity(0.32) : Theme.Brand.navy.opacity(0.32),
                dotOpacity: 0.32
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
        // The panel is navy in both themes (never a bright/light surface the chip sits on), so
        // the chip's own ink stays white in both themes too — no colorScheme branch needed here.
        // A light-theme-specific "navy ink for contrast" branch existed before for a contrast
        // concern that assumed a lighter panel; it doesn't apply to this panel's actual color.
        let valueColor: Color = .white
        let eyebrowColor: Color = isLow ? .white.opacity(0.85) : Theme.Semantic.textSecondary.opacity(0.8)

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
                    .fill(isLow ? Color.black.opacity(0.25) : Color.white.opacity(0.18))
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
                // Orange only for low battery, in both themes — design/DESIGN_GUIDE.md §8's own
                // light-mode reference (02, 06, ...) shows a plain glass border on a normal-battery
                // chip in light theme too; an earlier "always orange in light theme" special case
                // here (for a white-on-white contrast concern that reference never actually shows)
                // didn't match it.
                .strokeBorder(isLow ? Theme.Brand.orange : Theme.Semantic.glassStroke, lineWidth: 1)
        )
        // §9.5 "Battery crossing 15%": "Chip color crossfades to orange over 250 ms, then the
        // pulse starts" — the fill/border/ink swaps above are already driven by `isLow`, so a
        // single animation binding on it crossfades the whole chip together.
        .animation(reduceMotion ? .easeInOut(duration: 0.16) : .easeInOut(duration: 0.25), value: isLow)
        // §9.4 "Low battery chip": "Orange glow ring expands from 0 to 8 pt while fading from 50%
        // to 0%" — an actual expanding ring, not a fixed-radius shadow pulse (a plain `.shadow`
        // has no size to animate, only opacity/radius-of-blur, which isn't the same shape).
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Theme.Brand.orange, lineWidth: 1.5)
                .padding(-(lowBatteryPulse ? MotionConstants.lowBatteryChipGlowMaxRadius : 0))
                .opacity(isLow ? (lowBatteryPulse ? 0 : MotionConstants.lowBatteryChipGlowMaxOpacity) : 0)
        )
        .onAppear {
            guard isLow, !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: MotionConstants.lowBatteryChipGlowHalfCycle).repeatForever(autoreverses: true)
            ) { lowBatteryPulse = true }
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
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: Color.green.opacity(0.85), radius: 4)
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

/// §9.1 point 6: "each block fades in and rises 6 pt, ease out 260 ms," delayed from the start of
/// the expand per `MotionConstants.staggerDelay(for:)`. §9.6: "No stagger" under Reduce Motion —
/// the block just renders at its resting position/opacity immediately, letting the parent card's
/// own 160 ms crossfade (NotchView) carry it instead.
///
/// Fires once per expand, not on every re-render: `.onAppear` only runs on genuine insertion into
/// the view hierarchy, and ExpandedCard (and so every block inside it) is torn down on each
/// collapse and rebuilt fresh on the next expand — never kept alive and merely re-evaluated while
/// already showing, the same assumption the guide's own sample `StaggerIn` code makes.
private struct StaggerIn: ViewModifier {
    let block: MotionConstants.ContentBlock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || shown ? 1 : 0)
            .offset(y: reduceMotion || shown ? 0 : MotionConstants.staggerRiseDistance)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeOut(duration: MotionConstants.staggerDuration)
                        .delay(MotionConstants.staggerDelay(for: block))
                ) { shown = true }
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
