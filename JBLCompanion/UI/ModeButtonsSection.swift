import SwiftUI

/// The expanded card's mode-controls slot — design/DESIGN_GUIDE.md §4 "Mode buttons"/"Status
/// line", §9.3 "Choosing a mode". Four standalone buttons (no shared track) plus the status line,
/// or the "not available for this model" note row when the connected profile doesn't support
/// noise control at all.
///
/// All of this is presentation over `ModeButtonResolver` + the existing
/// `NoiseModeRequestCoordinator`/`NoiseControlCommander` path (via the closures NotchView already
/// threads through from AppDelegate) — nothing here owns Bluetooth state, the rate limit, or the
/// 2s timeout.
struct ModeButtonsSection: View {
    let state: HeadphoneState
    let dock: CardDock
    let isModeVerified: (CommandableNoiseMode) -> Bool
    let supportsNoiseControl: Bool
    let onSelectNoiseMode: (CommandableNoiseMode) -> Void

    @Namespace private var modeFill

    private var isVertical: Bool { dock.isVertical }
    /// Same gate the old segmented control used: a disconnected device has no "unsupported model"
    /// to report yet, so it falls through to the (all-disabled) buttons instead of the note row.
    private var showsNoteRow: Bool { state.connection == .connected && !supportsNoiseControl }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsNoteRow {
                NoteRow()
            } else {
                buttons
                StatusLineView(content: statusLineContent)
            }
        }
    }

    /// Off, ANC, Ambient, TalkThru — design/DESIGN_GUIDE.md §4 and every mode-button reference
    /// image. Deliberately not `CommandableNoiseMode.allCases`: that enum's declaration order
    /// (off, anc, talkThru, ambientAware) puts TalkThru before Ambient, which doesn't match.
    private static let displayOrder: [CommandableNoiseMode] = [.off, .anc, .ambientAware, .talkThru]

    @ViewBuilder
    private var buttons: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(spacing: 6))
        layout {
            ForEach(Self.displayOrder, id: \.self) { mode in
                ModeButtonView(
                    mode: mode, dock: dock, namespace: modeFill,
                    resolvedState: ModeButtonResolver.state(
                        for: mode, isModeVerified: isModeVerified(mode),
                        currentMode: state.noiseMode, pendingMode: state.pendingNoiseMode
                    ),
                    isInteractive: ModeButtonResolver.isInteractive(
                        for: mode, isModeVerified: isModeVerified(mode),
                        currentMode: state.noiseMode, pendingMode: state.pendingNoiseMode
                    ),
                    pendingNoiseMode: state.pendingNoiseMode,
                    noiseModeConfirmationTimedOut: state.noiseModeConfirmationTimedOut,
                    onSelect: { onSelectNoiseMode(mode) }
                )
            }
        }
        // Ties the sliding-fill matchedGeometryEffect (and the old button's fade back to
        // available) to the one spring the guide specifies for a confirmation — §9.3's
        // `Animation.spring(response: 0.30, dampingFraction: 0.82)`. Bound to `noiseMode`
        // specifically (not `pendingNoiseMode`) so entering pending stays a direct, unanimated
        // snap ("goes pending right away") — `handleConfirmation` changes both in the same
        // transaction, so this one binding covers the whole confirm-step diff.
        .animation(
            reduceMotionAnimation ?? .spring(response: 0.30, dampingFraction: 0.82),
            value: state.noiseMode
        )
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var reduceMotionAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.16) : nil
    }

    private var statusLineContent: StatusLineContent {
        ModeButtonResolver.statusLine(
            currentMode: state.noiseMode, pendingMode: state.pendingNoiseMode,
            timedOut: state.noiseModeConfirmationTimedOut, eventMapVerified: state.noiseModeEventMapVerified
        )
    }
}

// MARK: - One button

private struct ModeButtonView: View {
    let mode: CommandableNoiseMode
    let dock: CardDock
    let namespace: Namespace.ID
    let resolvedState: ModeButtonState
    let isInteractive: Bool
    let pendingNoiseMode: CommandableNoiseMode?
    let noiseModeConfirmationTimedOut: Bool
    let onSelect: () -> Void

    @State private var isHovered = false
    @State private var shakeTrigger = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVertical: Bool { dock.isVertical }
    private var iconAssetName: String {
        switch mode {
        case .off: return "IconOff"
        case .anc: return "IconANC"
        case .ambientAware: return "IconAmbient"
        case .talkThru: return "IconTalkThru"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            content
                .frame(maxWidth: .infinity, alignment: isVertical ? .leading : .center)
                .frame(height: isVertical ? 40 : 52)
                .padding(isVertical ? 12 : 0)
                .background {
                    // The sliding orange fill (§9.3): a single shape shared across all four
                    // buttons via matchedGeometryEffect, so it travels between them instead of
                    // one fading out while another fades in. Every other state paints its own
                    // plain, non-traveling fill.
                    if resolvedState == .active {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.Brand.orange)
                            .matchedGeometryEffect(id: "modeFill", in: namespace)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fillColor)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
                .overlay {
                    if resolvedState == .pending && !reduceMotion {
                        PendingBorderPulse()
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .onHover { isHovered = $0 }
        .modifier(Shake(animatableData: CGFloat(shakeTrigger)))
        .onChange(of: pendingNoiseMode) { old, new in
            guard old == mode, new == nil, noiseModeConfirmationTimedOut, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.24)) { shakeTrigger += 1 }
        }
        .animation(.easeOut(duration: 0.18), value: isHovered)
    }

    @ViewBuilder
    private var content: some View {
        if isVertical {
            HStack(spacing: 10) {
                iconSlot
                Text(mode.displayText)
                    .font(Theme.Fonts.modeLabel(sideDock: true))
                    .foregroundStyle(.white.opacity(labelOpacity))
                Spacer(minLength: 0)
                if resolvedState == .disabled {
                    Text("SOON")
                        .font(Theme.Fonts.soonTag(sideDock: true))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        } else {
            VStack(spacing: 5) {
                if resolvedState == .disabled {
                    HStack(spacing: 3) {
                        Image("IconLock")
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 10, height: 10)
                        Text("SOON")
                            .font(Theme.Fonts.soonTag())
                            .tracking(0.6)
                    }
                    .foregroundStyle(.white.opacity(0.55))
                } else {
                    iconSlot
                }
                Text(mode.displayText)
                    .font(Theme.Fonts.modeLabel())
                    .foregroundStyle(.white.opacity(labelOpacity))
            }
        }
    }

    @ViewBuilder
    private var iconSlot: some View {
        switch resolvedState {
        case .pending:
            PendingRingView()
        case .disabled:
            // Side docks only — row docks fold the lock into the "SOON" row above (see `content`).
            Image("IconLock")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .foregroundStyle(.white.opacity(0.4))
        default:
            Image(iconAssetName)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(.white)
        }
    }

    private var labelOpacity: Double {
        switch resolvedState {
        case .active, .pending: return 1
        case .available: return isHovered ? 1 : 0.72
        case .disabled: return 0.38
        }
    }

    private var fillColor: Color {
        switch resolvedState {
        case .active: return .clear // painted by the matchedGeometryEffect layer instead.
        case .available: return isHovered ? Color.white.opacity(0.08) : Theme.Semantic.buttonFill
        case .pending: return Theme.Semantic.buttonFill
        case .disabled: return .clear
        }
    }

    private var borderColor: Color {
        switch resolvedState {
        case .active: return Theme.Semantic.buttonStrokeActive
        case .available: return isHovered ? Theme.Semantic.buttonStrokeHover : Theme.Semantic.buttonStroke
        case .pending: return Theme.Brand.orange.opacity(0.55)
        case .disabled: return Theme.Semantic.buttonStrokeDisabled
        }
    }
}

// MARK: - Pending ring (§9.3)

private struct PendingRingView: View {
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.Brand.orange, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        // Exempt from Reduce Motion (§9.6): this fill carries information (how much of the 2s
        // confirmation window is left), so it keeps animating even when other loops stop. Driven
        // by a fixed-duration local animation, not a live countdown, because HeadphoneState has no
        // "request started at" timestamp to read — this view is simply recreated (onAppear fires
        // fresh) each time a button newly becomes pending, naturally resyncing the fill.
        .onAppear { withAnimation(.linear(duration: 2.0)) { progress = 1 } }
    }
}

/// The extra 1.5pt ring 3pt outside the button, pulsing 0-60% opacity on a 1.1s loop while
/// pending (§9.3 "Pending border pulse") — decorative, so (unlike the ring above) it stops under
/// Reduce Motion; the caller only mounts this view when `!reduceMotion`.
private struct PendingBorderPulse: View {
    @State private var isVisible = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Theme.Brand.orange, lineWidth: 1.5)
            .padding(-3)
            .opacity(isVisible ? 0.6 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { isVisible = true }
            }
    }
}

/// Two swings of 4pt over 240ms (§9.3 "Timeout shake").
private struct Shake: GeometryEffect {
    var travel: CGFloat = 4
    var shakes: CGFloat = 2
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * 2 * shakes), y: 0))
    }
}

// MARK: - Status line (§4 "Status line")

private struct StatusLineView: View {
    let content: StatusLineContent

    var body: some View {
        HStack(spacing: 7) {
            dot
            Group {
                if content.detail.isEmpty {
                    Text(content.modeName).font(Theme.Fonts.statusModeName)
                } else {
                    Text(content.modeName).font(Theme.Fonts.statusModeName)
                        + Text(" " + content.detail).font(Theme.Fonts.statusDetail)
                }
            }
            .foregroundStyle(Theme.Semantic.textSecondary)
        }
    }

    @ViewBuilder
    private var dot: some View {
        switch content.dotStyle {
        case .solidGlow:
            Circle()
                .fill(Theme.Brand.orange)
                .frame(width: 7, height: 7)
                .shadow(color: Theme.Brand.orange.opacity(0.85), radius: 4)
        case .pulsingRing:
            PulsingStatusDot()
        case .stillRing:
            Circle()
                .strokeBorder(Theme.Brand.orange, lineWidth: 1.7)
                .frame(width: 7, height: 7)
        }
    }
}

/// Opacity 0.3 to 1 and back, 1.1s full cycle (§9.4 "Pulsing status dot") — one of the two loops
/// that keep running under Reduce Motion (§9.6), since it's carrying live "still waiting"
/// information, same reasoning as `PendingRingView`.
private struct PulsingStatusDot: View {
    @State private var isBright = false

    var body: some View {
        Circle()
            .strokeBorder(Theme.Brand.orange, lineWidth: 1.7)
            .frame(width: 7, height: 7)
            .opacity(isBright ? 1 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { isBright = true }
            }
    }
}

// MARK: - Note row (670NC-style "controls not available" — §4 "Status line")

private struct NoteRow: View {
    var body: some View {
        HStack(spacing: 7) {
            Image("IconInfo")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(.white)
            Text("Controls not available for this model yet")
                .font(Theme.Fonts.subText)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.Semantic.glassFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1)
        )
    }
}

// MARK: - Previews (design/DESIGN_GUIDE.md §4; design/reference/18, 26, 01, 05, 09)

#if DEBUG
/// `@Namespace` needs a View's own storage — previews can't declare a property wrapper inline in
/// a `#Preview` closure, so this just hosts one for `ModeButtonView`'s required `namespace:` arg.
private struct ButtonStatesPreview: View {
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 16) {
            stateColumn("Active", .active)
            stateColumn("Available", .available)
            stateColumn("Pending", .pending)
            stateColumn("Disabled", .disabled)
        }
        .padding(24)
    }

    private func stateColumn(_ title: String, _ resolvedState: ModeButtonState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ModeButtonView(
                mode: resolvedState == .disabled ? .off : .anc, dock: .top, namespace: ns,
                resolvedState: resolvedState, isInteractive: resolvedState == .available,
                pendingNoiseMode: resolvedState == .pending ? .anc : nil,
                noiseModeConfirmationTimedOut: false, onSelect: {}
            )
            .frame(width: 140)
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

#Preview("Button states - Dark") {
    ButtonStatesPreview().background(Color.black).preferredColorScheme(.dark)
}

#Preview("Button states - Light") {
    ButtonStatesPreview().background(Theme.Semantic.panelBase).preferredColorScheme(.light)
}

@MainActor
private func previewSectionState(noiseMode: NoiseMode = .anc, pending: CommandableNoiseMode? = nil, timedOut: Bool = false) -> HeadphoneState {
    let state = HeadphoneState()
    state.connection = .connected
    state.noiseMode = noiseMode
    state.pendingNoiseMode = pending
    state.noiseModeConfirmationTimedOut = timedOut
    return state
}

#Preview("Row layout - Dark") {
    ModeButtonsSection(
        state: previewSectionState(), dock: .top, isModeVerified: { $0 != .off },
        supportsNoiseControl: true, onSelectNoiseMode: { _ in }
    )
    .padding(24).frame(width: 340).background(Theme.Semantic.panelBase).preferredColorScheme(.dark)
}

#Preview("Row layout - Light") {
    ModeButtonsSection(
        state: previewSectionState(), dock: .top, isModeVerified: { $0 != .off },
        supportsNoiseControl: true, onSelectNoiseMode: { _ in }
    )
    .padding(24).frame(width: 340).background(Theme.Semantic.panelBase).preferredColorScheme(.light)
}

#Preview("Side-dock layout - Dark") {
    ModeButtonsSection(
        state: previewSectionState(pending: .ambientAware), dock: .left, isModeVerified: { $0 != .off },
        supportsNoiseControl: true, onSelectNoiseMode: { _ in }
    )
    .padding(24).frame(width: 260).background(Theme.Semantic.panelBase).preferredColorScheme(.dark)
}

#Preview("Side-dock layout - Light") {
    ModeButtonsSection(
        state: previewSectionState(pending: .ambientAware), dock: .left, isModeVerified: { $0 != .off },
        supportsNoiseControl: true, onSelectNoiseMode: { _ in }
    )
    .padding(24).frame(width: 260).background(Theme.Semantic.panelBase).preferredColorScheme(.light)
}

#Preview("Timed out - Dark") {
    ModeButtonsSection(
        state: previewSectionState(noiseMode: .ambientAware, timedOut: true), dock: .top,
        isModeVerified: { $0 != .off }, supportsNoiseControl: true, onSelectNoiseMode: { _ in }
    )
    .padding(24).frame(width: 340).background(Theme.Semantic.panelBase).preferredColorScheme(.dark)
}

#Preview("Not supported - Dark") {
    ModeButtonsSection(
        state: previewSectionState(), dock: .top, isModeVerified: { _ in false },
        supportsNoiseControl: false, onSelectNoiseMode: { _ in }
    )
    .padding(24).frame(width: 340).background(Theme.Semantic.panelBase).preferredColorScheme(.dark)
}
#endif
