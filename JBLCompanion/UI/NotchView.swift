import SwiftUI

/// Transient presentation state for the notch panel (expanded/collapsed). Deliberately separate
/// from HeadphoneState, which is device state, not UI state.
@Observable
@MainActor
final class NotchUIState {
    var isExpanded: Bool = false
}

/// Just the island's content — collapsed glyph+ring or the expanded card. The shape itself
/// (silhouette, resize animation) is NotchSilhouetteView, a native CAShapeLayer-backed view this
/// sits on top of; NotchView never draws its own background or shape.
struct NotchView: View {
    let state: HeadphoneState
    let uiState: NotchUIState
    let collapsedSize: CGSize
    let onSelectNoiseMode: (CommandableNoiseMode) -> Void
    /// Per-mode "is this command frame hardware-verified" check (Tune770NCProfile.isModeVerified)
    /// — only verified modes' segments are tappable. Off has no command frame at all (none has
    /// ever been captured), so its segment stays visible but permanently disabled rather than
    /// disappearing — see NoiseControlCommander.commandFrame's doc comment.
    let isModeVerified: (CommandableNoiseMode) -> Bool
    /// Whether the connected device's own model has noise control wired up at all
    /// (DeviceProfile.supportsNoiseControl) — false hides the segmented control entirely in favor
    /// of a "not available" message, distinct from a verified-but-disabled segment.
    let supportsNoiseControl: () -> Bool
    /// Whether the active display's menu bar is a physical notch (NotchPanel.isNotched) — a
    /// closure, not a frozen Bool, since NotchPanel builds this NotchView once at init and never
    /// reconstructs it, so a plain value would never reflect a later display change. Drives
    /// CollapsedPill's always-black, square-top notch variant.
    let isNotched: () -> Bool
    /// The expanded card's cut-out tab collapses the card when tapped (design/DESIGN_GUIDE.md §4)
    /// — a closure, like the other NotchPanel-owned behaviors, since collapsing is a real window/
    /// silhouette transition NotchPanel owns, not something NotchView can trigger by itself.
    let onCollapseTabTapped: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// JBL's own brand orange — used sparingly, as the one accent color against the black shape.
    private let accent = Color(red: 1.0, green: 0.45, blue: 0.05)

    var body: some View {
        Group {
            if uiState.isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var collapsedContent: some View {
        CollapsedPill(variant: pillVariant)
            .frame(width: collapsedSize.width, height: collapsedSize.height)
    }

    /// Bridges live app state to PillVariant.resolve — the app only ever docks to the top today
    /// (NotchPanel has no left/right/bottom placement logic yet) and never produces a real
    /// "connecting" signal (HeadphoneState has no such state), so those PillVariant cases are
    /// exercised by CollapsedPill's own previews/tests but not reachable from here.
    private var pillVariant: PillVariant {
        PillVariant.resolve(
            device: state.connection == .connected ? .matched(photo: state.photoAssetNames) : .noDevice,
            connection: .connected,
            batteryPercent: state.batteryPercent,
            theme: colorScheme == .dark ? .dark : .light,
            dock: .top(isNotched: isNotched())
        )
    }

    @ViewBuilder
    private var expandedContent: some View {
        // Only the top dock is reachable from live app state today — see ExpandedCard's own doc
        // comment for why bottom/left/right exist (pure logic/previews) but aren't wired in yet.
        ExpandedCard(state: state, dock: .top, onCollapseTapped: onCollapseTabTapped) {
            noiseControlSection
        }
    }

    @ViewBuilder
    private var noiseControlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOISE CONTROL")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.4))

            if state.connection == .connected && !supportsNoiseControl() {
                Text("Controls not available for this model yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                modeSegments
                statusCaption
            }
        }
    }

    /// A hand-built segmented control, not SwiftUI's native `.pickerStyle(.segmented)` — that
    /// style can only enable/disable the whole control at once, and individual segments need to
    /// be independently disabled here based on `isModeVerified`.
    @ViewBuilder
    private var modeSegments: some View {
        let selected = state.pendingNoiseMode ?? state.noiseMode.commandable
        HStack(spacing: 2) {
            ForEach(CommandableNoiseMode.allCases, id: \.self) { mode in
                let verified = isModeVerified(mode)
                let isSelected = selected == mode
                Button {
                    onSelectNoiseMode(mode)
                } label: {
                    Text(segmentLabel(mode))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.black : .white.opacity(verified ? 0.85 : 0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? accent : Color.white.opacity(0.001), // near-invisible but still hit-testable
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(state.pendingNoiseMode != nil || !verified)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func segmentLabel(_ mode: CommandableNoiseMode) -> String {
        switch mode {
        case .off: return "Off"
        case .anc: return "ANC"
        case .talkThru: return "TalkThru"
        case .ambientAware: return "Ambient"
        }
    }

    @ViewBuilder
    private var statusCaption: some View {
        switch (state.pendingNoiseMode, state.noiseModeConfirmationTimedOut) {
        case (.some(let pending), _):
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(accent)
                Text("Setting \(pending.displayText)…")
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
            }
        case (nil, true):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("No confirmation")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.orange)
        case (nil, false):
            Text(NoiseModeStatusText.format(mode: state.noiseMode, eventMapVerified: state.noiseModeEventMapVerified))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
