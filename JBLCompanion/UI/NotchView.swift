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
            ModeButtonsSection(
                state: state, dock: .top, isModeVerified: isModeVerified,
                supportsNoiseControl: supportsNoiseControl(), onSelectNoiseMode: onSelectNoiseMode
            )
        }
    }
}
