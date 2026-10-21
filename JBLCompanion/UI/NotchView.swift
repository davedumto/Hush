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
    /// True only for the duration of an edge switch's internal collapse-move-expand cycle
    /// (`DockPlacement.edgeChangeOrdering`'s `.collapseFirst` case — currently unreachable: the
    /// only way to change edges is dragging, and dragging is only ever allowed while already
    /// collapsed, so there's never a card to collapse first; kept in case a future non-drag way
    /// to switch edges while expanded gets added. design/DESIGN_GUIDE.md §6: "collapse first,
    /// move the pill, then expand from the new edge"). That rule is about the *card's*
    /// own shape motion (and is still followed below, unaffected by this flag) — not the hero
    /// photo's own fly-to-the-pill flight (§9.1 point 5), which owner feedback flagged as
    /// reading like a glitch here: the photo starts trailing toward the pill, then the pill
    /// instantly teleports to the new edge mid-flight, so the animation looks like it "catches
    /// itself" and the photo drops out, rather than completing. That flight is correct for an
    /// actual user-initiated collapse/expand; it's only this one, internally-triggered cycle
    /// that should skip it and let the photo just fade with the rest of the card instead.
    var isRepositioningEdge: Bool = false
    /// Bumped by NotchPanel.requestOpenIslandSettings() — the fallback NSStatusItem menu's own
    /// "Island Settings…" item. AppDelegate (plain AppKit) has no SwiftUI environment of its own
    /// to call `openWindow` from directly, so it goes through this instead: NotchView is the one
    /// always-mounted SwiftUI view in the whole app (see the body's own doc comment on why the
    /// pill never leaves the tree), so it's the one place that can actually hold an
    /// `@Environment(\.openWindow)` and act on a change here. A counter, not a Bool, so requesting
    /// it twice in a row (the window already open, re-clicking the menu item) still fires the
    /// `.onChange` both times instead of only the first.
    var islandSettingsRequestToken: Int = 0
    /// Bumped by NotchPanel.requestOpenFeedback() — same pattern and same reason as
    /// islandSettingsRequestToken above.
    var feedbackRequestToken: Int = 0
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
    /// Non-nil only when docked flush into a screen corner (NotchPanel.dockedCorner's own doc
    /// comment) — a closure, same reasoning as `dockEdge`/`isNotched`. Drives `ExpandedCard`'s own
    /// corner-tab placement.
    let dockedCorner: () -> ScreenCorner?
    /// Free-floating only — which edge of the card the cut-out notch sits on, how far along it,
    /// and where that same position falls as a 0...1 `UnitPoint` (NotchPanel.freeFloatingNotch()'s
    /// own doc comment), so both the notch itself and the open/close animation's own anchor stay
    /// aligned with the island instead of centered on whichever edge the card happens to render
    /// flush against. `nil` for every other placement mode.
    let freeFloatingNotch: () -> (dock: CardDock, offset: CGFloat, anchor: UnitPoint)?
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
    /// NotchUIState.islandSettingsRequestToken's own doc comment — this is the one place in the
    /// app that can actually call it.
    @Environment(\.openWindow) private var openWindow
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
        .onChange(of: uiState.islandSettingsRequestToken) { _, newValue in
            guard newValue > 0 else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: IslandSettingsView.windowID)
        }
        .onChange(of: uiState.feedbackRequestToken) { _, newValue in
            guard newValue > 0 else { return }
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: FeedbackView.windowID)
        }
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
            .scale(scale: MotionConstants.cardTransitionScale, anchor: cardTransitionAnchor)
            .combined(with: .opacity)
    }

    /// `dockEdge().edgeUnitPoint` on its own (`.top`/`.bottom` — always horizontally *centered*,
    /// `(0.5, 0)`/`(0.5, 1)`) is right for a plain, centered edge dock, but wrong for a corner one:
    /// the window itself grows from a *fixed corner point* (NotchPanel.windowFrame(for:)'s own doc
    /// comment on why), not a centered edge, so a centered scale anchor fights that — the card
    /// visibly grows symmetrically left/right from the middle while the window around it is
    /// actually anchored off to one side, reading as "growing from the top" (centered, ordinary)
    /// even when docked at a corner, or as growing the wrong direction entirely. Biasing the
    /// anchor to the real corner (its own top-left/top-right/bottom-left/bottom-right UnitPoint)
    /// instead makes the animation agree with where the window is actually anchored.
    private var cardTransitionAnchor: UnitPoint {
        // Owner spec, step 3: a free-floating tray's own animation originates from the island's
        // actual position — checked first, since `isFreePositioned` and `dockedCorner` are
        // mutually exclusive placement modes (NotchPanel.dockedCorner's own doc comment).
        if let notch = freeFloatingNotch() { return notch.anchor }
        guard let corner = dockedCorner() else { return dockEdge().edgeUnitPoint }
        switch corner {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    @ViewBuilder
    private var collapsedContent: some View {
        let size = collapsedSize()
        CollapsedPill(variant: pillVariant, diameter: IslandSettings.pillDiameter, photoNamespace: pillPhotoNamespace)
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
    /// showed as a stray sliver at the screen edge (left/right).
    ///
    /// Only drop the shared id during the one state that actually caused that: fully expanded and
    /// settled (`isExpanded && !isAnimating`). Every other state — resting collapsed, and both
    /// directions of the swing — keeps it, deliberately wider than gating on `isAnimating` alone:
    /// severing the link right as `isAnimating` first flips true (the same render pass that
    /// re-inserts ExpandedCard, e.g. right after an edge-switch's collapse-move-expand cycle) gave
    /// matchedGeometryEffect nothing "warm" to interpolate the hero photo from on its very first
    /// frame — a brief missing-image flash before it caught up. Keeping the pill's side of the id
    /// continuously live through the whole collapsed lifecycle, right up to the moment it's needed,
    /// avoids that cold start while still protecting the settled-expanded state.
    ///
    /// `isRepositioningEdge` overrides all of that to `nil`: see its own doc comment — an edge
    /// switch's internal collapse/expand shouldn't fly the photo to the pill at all.
    private var pillPhotoNamespace: Namespace.ID? {
        guard !uiState.isRepositioningEdge else { return nil }
        return (!uiState.isExpanded || uiState.isAnimating) ? photoFlight : nil
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
            state: state, dock: dockEdge().cardDock, dockedCorner: dockedCorner(), freeFloatingNotch: freeFloatingNotch(),
            onCollapseTapped: onCollapseTabTapped,
            isModeVerified: isModeVerified,
            supportsNoiseControl: supportsNoiseControl(), onSelectNoiseMode: onSelectNoiseMode,
            onReconnectTapped: onReconnectTapped, onOpenBluetoothSettingsTapped: onOpenBluetoothSettingsTapped,
            lastMatchedProfileDisplayName: lastMatchedProfileDisplayName(), photoNamespace: cardPhotoNamespace
        )
    }

    /// See `isRepositioningEdge`'s own doc comment — the card's own half of the same suppression
    /// `pillPhotoNamespace` applies to the pill's.
    private var cardPhotoNamespace: Namespace.ID? {
        uiState.isRepositioningEdge ? nil : photoFlight
    }
}
