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
    /// True for the whole duration of an expand/collapse swing (set in NotchPanel.present(),
    /// cleared once it settles) — NotchView's own pill-visibility logic needs this in addition to
    /// `isExpanded`: `isExpanded` flips to its new value at the very *start* of a swing, not once
    /// it finishes, so on a collapse specifically "not expanded" is already true for the whole
    /// ~280ms the card is still visibly shrinking away on top of the pill. Revealing the pill
    /// right then showed it alongside the still-shrinking card the entire time, not just once the
    /// card was actually gone.
    var isAnimating: Bool = false
    /// Bumped by NotchPanel every time edge/offset/geometry/display changes outside of an
    /// expand/collapse transition. `dockEdge()`/`isNotched()`/`collapsedSize()` are plain closures
    /// over NotchPanel's own internal state, which isn't itself Observable, so without something
    /// here for NotchView to read, SwiftUI has no reason to re-invoke them until some *unrelated*
    /// state change (isExpanded, isAnimating, a Bluetooth update) happens to force a re-render.
    /// That let a dock-edge change switch CollapsedPill's internal layout (HStack vs VStack, for
    /// horizontal vs vertical docks) only once some other render happened to flush it through —
    /// the old layout's own background stayed visible underneath/behind the new one until then.
    var geometryVersion: Int = 0
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
        // Establishes an Observation dependency on NotchPanel's own edge/geometry state, even
        // though the value itself is never used below — see NotchUIState.geometryVersion's own
        // doc comment for why this is necessary (dockEdge()/isNotched()/collapsedSize() alone
        // give SwiftUI no reason to re-evaluate this body when only *they* change).
        let _ = uiState.geometryVersion
        // The pill is always mounted, in its one stable, correct position — never conditionally
        // inserted/removed, never part of SwiftUI's `.transition()` system at all. Repeated real-
        // hardware testing showed the pill, specifically, rendering in the wrong place for a frame
        // or two during its own insertion/removal transition, surviving several independent
        // geometry fixes (window envelope sizing, forced layout passes, explicit stack sizing, the
        // collapsedSize race) — the transition system itself was the common factor every time.
        // Instead: hide it with a plain, unanimated opacity flip the instant the card is about to
        // cover it, and let it reappear the same way, instantly, the instant the card goes away —
        // `.transaction { $0.animation = nil }` strips any animation from *this* opacity change
        // specifically, regardless of the `withAnimation` the card's own transition below runs
        // under in the same update. The card, confirmed correct across every one of those same
        // fixes, keeps its own `.transition()` — only the pill's own position/visibility needed to
        // stop being animated, not the whole crossfade.
        ZStack(alignment: dockEdge().edgeAlignment) {
            collapsedContent
                .opacity(isPillVisible ? 1 : 0)
                .allowsHitTesting(isPillVisible)
                .transaction { $0.animation = nil }

            if uiState.isExpanded {
                expandedContent
                    .transition(cardTransition)
            }
        }
        // Explicit, not left to size itself off whichever children happen to be mounted — see the
        // card's own insertion/removal above: with no frame of its own, this ZStack's ideal size
        // would jump between the pill's and the card's depending on which happens to be mounted,
        // in the very same transaction as whichever one is animating. Pinning this to `.infinity`
        // ties the stack's size to hosting's own externally-set AppKit frame instead (stable for
        // the whole swing — see NotchPanel.present()'s own doc comment on `contentLayoutSize`).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    /// On expand, hide immediately — `isExpanded` flipping to true is reason enough on its own.
    /// On collapse, `isExpanded` flips to false at the very *start* of the swing too, well before
    /// the card has actually finished shrinking away, so that alone isn't enough: wait for
    /// `isAnimating` to clear as well, so the pill only reappears once the card is actually gone.
    private var isPillVisible: Bool {
        !uiState.isExpanded && !uiState.isAnimating
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

    @ViewBuilder
    private var collapsedContent: some View {
        let size = collapsedSize()
        CollapsedPill(variant: pillVariant, photoNamespace: pillPhotoNamespace)
            .frame(width: size.width, height: size.height)
    }

    /// The pill is always mounted (see the body's own doc comment on why), so without this gate
    /// it would share `photoFlight`'s matchedGeometryEffect id with ExpandedCard's hero photo for
    /// the *entire* time both happen to be in the tree — not just during the actual flight.
    /// `NotchUIState.geometryVersion`'s own doc comment describes exactly the case that broke:
    /// switching dock edges while already expanded re-lays-out this still-mounted (just invisible)
    /// pill at the new edge's position, and with both views sharing one matchedGeometryEffect id
    /// at that moment, SwiftUI snapped the already-settled card's photo down to the pill's small,
    /// edge-anchored frame — the photo either vanished (clipped inside the card at top/bottom) or
    /// showed as a stray sliver at the screen edge (left/right). Only share the id while a flight
    /// could actually be happening (`isAnimating` covers the whole expand/collapse swing, per
    /// `NotchPanel.present()`), so a later geometry-only change can't re-sync it once settled.
    private var pillPhotoNamespace: Namespace.ID? {
        uiState.isAnimating ? photoFlight : nil
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
