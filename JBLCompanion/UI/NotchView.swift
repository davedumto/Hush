import SwiftUI

/// Bridges the pure geometry-layer `DockEdge` (DockPlacement.swift) to the view-layer dock
/// vocabulary `CardDock`/`PillDock` already use — a 1:1 mapping, kept here rather than in
/// DockPlacement.swift so that file stays framework-free (it only needs Foundation/CoreGraphics).
extension DockEdge {
    var cardDock: CardDock {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        }
    }

    func pillDock(isNotched: Bool) -> PillDock {
        switch self {
        case .top: return .top(isNotched: isNotched)
        case .bottom: return .bottom
        case .left: return .left
        case .right: return .right
        }
    }

    /// design/DESIGN_GUIDE.md §9.1 point 2: "anchored on the docked edge (top centre for top,
    /// bottom centre for bottom, leading centre for left, trailing centre for right)" — both
    /// where the card's own scale transition anchors and where NotchView's ZStack aligns the
    /// (much smaller) pill within the card-sized content frame during a transition.
    var edgeAlignment: Alignment {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }

    var edgeUnitPoint: UnitPoint {
        switch self {
        case .top: return .top
        case .bottom: return .bottom
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

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
    /// A closure, not a frozen CGSize: NotchPanel builds this NotchView once, but the collapsed
    /// pill's own size can change later (a dock-edge change, or an Island Settings change to the
    /// top-dock capsule/notch sizing).
    let collapsedSize: () -> CGSize
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
    /// Which screen edge the island is currently docked to (design/DESIGN_GUIDE.md §6) — a
    /// closure, same reasoning as `isNotched`: NotchPanel builds this NotchView once, but the
    /// edge can change later (drag, Island Settings, a screen change).
    let dockEdge: () -> DockEdge
    /// The expanded card's cut-out tab collapses the card when tapped (design/DESIGN_GUIDE.md §4)
    /// — a closure, like the other NotchPanel-owned behaviors, since collapsing is a real window/
    /// silhouette transition NotchPanel owns, not something NotchView can trigger by itself.
    let onCollapseTabTapped: () -> Void
    /// design/DESIGN_GUIDE.md §5 "No headphones": re-runs classic detection and the RFCOMM open
    /// through AppDelegate's existing entry points.
    let onReconnectTapped: () -> Void
    /// Opens System Settings' Bluetooth pane — plain AppKit, no Bluetooth protocol involved.
    let onOpenBluetoothSettingsTapped: () -> Void
    /// A closure, not a frozen value, for the same reason `isNotched` is: NotchPanel builds this
    /// NotchView once at init, so a plain value read at construction time would never reflect a
    /// later UserDefaults change (AppDelegate persists this on every classic-connect match).
    let lastMatchedProfileDisplayName: () -> String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// design/DESIGN_GUIDE.md §9.1 point 5 "Photo flight": owned by this common ancestor and
    /// threaded into both CollapsedPill and ExpandedCard, so `matchedGeometryEffect` can morph the
    /// pill's own photo into the hero photo across the expand/collapse transition below.
    @Namespace private var photoFlight

    var body: some View {
        // A ZStack, not a plain Group — §9.1/§9.2 need the outgoing and incoming view to coexist
        // and cross-fade (pill scaling to 0.5 while the card scales up from 0.1, or the reverse),
        // not an instant swap. Aligned to the docked edge so the much-smaller pill lines up with
        // where the card's own edge sits, both within NotchPanel's content frame (sized to the
        // larger of the two for the whole transition — see NotchPanel.present()'s own doc comment
        // on `contentLayoutSize`).
        ZStack(alignment: dockEdge().edgeAlignment) {
            if uiState.isExpanded {
                expandedContent
                    .transition(cardTransition)
            } else {
                collapsedContent
                    .transition(pillTransition)
            }
        }
        // Explicit, not left to size itself off whichever children happen to be mounted: with no
        // frame of its own, this ZStack's ideal size is just its *current* child's ideal size —
        // the 46x34 pill's, right up until the instant the card is inserted alongside it, at
        // which point the stack's own ideal size jumps to the card's in the very same transaction
        // as the pill's own removal animation. Animating an alignment-positioned view's place
        // across a container that is itself resizing underneath it, in that same beat, is exactly
        // the kind of thing that reads as "renders in the wrong spot for a frame, then corrects" —
        // pinning this to `.infinity` ties the stack's size to hosting's own externally-set AppKit
        // frame instead (stable for the whole swing — see NotchPanel.present()'s own doc comment
        // on `contentLayoutSize`), never to its children's union.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    /// §9.1 point 2 / §9.2 point 2: anchored scale + fade. §9.6: "No scale, no blur, no overshoot"
    /// under Reduce Motion — a plain opacity crossfade instead.
    ///
    /// No `.blur()` here, despite the guide's own "blur 10 to blur 0": NotchPanel's content view
    /// hierarchy runs with `masksToBounds = false` on purpose (CollapsedPill/ExpandedCard's own
    /// shadows need real room to bleed past their nominal frame), and a `.blur()` transition bleeds
    /// exactly the same way, uncontained, into whatever's behind the window — a visibly broken,
    /// semi-transparent smear well past the card's own bounds instead of a soft edge. Scale + fade
    /// alone already reads as the card growing in; it just doesn't start in soft focus.
    private var cardTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return AnyTransition
            .scale(scale: MotionConstants.cardTransitionScale, anchor: dockEdge().edgeUnitPoint)
            .combined(with: .opacity)
    }

    /// §9.1 point 4 / §9.2 point 3: "the pill fades out/in and scales to/from 0.5." Plain opacity
    /// under Reduce Motion, same reasoning as `cardTransition`.
    private var pillTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(scale: MotionConstants.pillTransitionScale).combined(with: .opacity)
    }

    @ViewBuilder
    private var collapsedContent: some View {
        let size = collapsedSize()
        CollapsedPill(variant: pillVariant, photoNamespace: photoFlight)
            .frame(width: size.width, height: size.height)
    }

    /// design/DESIGN_GUIDE.md §5 "Connecting": the classic link is up but no status event has
    /// arrived yet — a derived signal (CardConditionResolver uses the same two facts for the
    /// card), never a new piece of raw Bluetooth state.
    private var isConnecting: Bool { state.connection == .connected && state.noiseMode == .unknown }

    /// Bridges live app state to PillVariant.resolve.
    private var pillVariant: PillVariant {
        PillVariant.resolve(
            device: state.connection == .connected ? .matched(photo: state.photoAssetNames) : .noDevice,
            connection: isConnecting ? .connecting : .connected,
            batteryPercent: state.batteryPercent,
            theme: colorScheme == .dark ? .dark : .light,
            dock: dockEdge().pillDock(isNotched: isNotched())
        )
    }

    @ViewBuilder
    private var expandedContent: some View {
        ExpandedCard(
            state: state, dock: dockEdge().cardDock, onCollapseTapped: onCollapseTabTapped, isModeVerified: isModeVerified,
            supportsNoiseControl: supportsNoiseControl(), onSelectNoiseMode: onSelectNoiseMode,
            onReconnectTapped: onReconnectTapped, onOpenBluetoothSettingsTapped: onOpenBluetoothSettingsTapped,
            lastMatchedProfileDisplayName: lastMatchedProfileDisplayName(), photoNamespace: photoFlight
        )
    }
}
