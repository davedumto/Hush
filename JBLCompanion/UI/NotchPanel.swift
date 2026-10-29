import AppKit
import SwiftUI
import os.log

extension NSScreen {
    /// Stable per-display identifier (survives an external monitor being unplugged/reconnected,
    /// unlike CGDirectDisplayID which can be reassigned). Used for the "chosen display" setting
    /// and for per-display dock edge/offset persistence.
    var stableDisplayUUIDString: String? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, uuidRef.takeRetainedValue()) as String
    }

    var notchDisplayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Borderless, non-activating overlay panel hosting the island: a native CAShapeLayer silhouette
/// (NotchSilhouetteView) with SwiftUI content (NotchView) layered on top. Ported from
/// vorssaint-utils's NotchPanel/NotchWindowHost/NotchService (geometry resolution, the
/// envelope-then-settle resize) — click-to-open/drag/four-edge docking (design/DESIGN_GUIDE.md §6,
/// §9.2) are this app's own additions on top of that base.
///
/// `.top` keeps using IslandGeometry's own frame (notch fusion — hanging flush under a real
/// camera — has no equivalent on the other three edges, and only matters on `.top` even there);
/// `.bottom`/`.left`/`.right` use the much simpler DockPlacement math.
/// `windowFrame(for:)`/`contentOrigin(for:envelopeSize:)` are the two places
/// that branch on the current edge — everything else (the envelope-then-settle resize itself,
/// silhouette animation, content reveal timing) is shared and edge-agnostic, unchanged from before
/// this task, per the task's own "keep the existing expand and collapse transitions working as
/// they are."
@MainActor
final class NotchPanel: NSPanel {
    static let overlayCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle
    ]
    /// Was `statusBar + 1` (above the menu bar's own status items, below native menus) — raised to
    /// `.popUpMenu` as a real, researched experiment for the Space-switch/app-switch blink the
    /// owner reported (a documented pattern for notch-style overlay panels, not a guess): the
    /// WindowServer may composite a window at this level differently across these transitions.
    /// Known tradeoff, explicitly accepted by the owner (2026-10-21): `.popUpMenu` sits *above*
    /// native menus, where `statusBar + 1` sat below them — the island can now render on top of a
    /// real dropdown/File/Edit menu if they happen to overlap, which couldn't happen before. If
    /// that reads as worse than the blink it was meant to fix, revert to `statusBar.rawValue + 1`.
    static let normalLevel = NSWindow.Level.popUpMenu

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "NotchPanel")

    private let headphoneState: HeadphoneState
    private let uiState = NotchUIState()
    private let onSelectNoiseMode: (CommandableNoiseMode) -> Void
    private let isModeVerified: (CommandableNoiseMode) -> Bool
    private let supportsNoiseControl: () -> Bool
    private let onReconnectTapped: () -> Void
    private let onOpenBluetoothSettingsTapped: () -> Void
    private let lastMatchedProfileDisplayName: () -> String?
    private let onPowerOff: () -> Void
    private let canPowerOff: () -> Bool
    private let canUseEqualizer: () -> Bool
    private let onSelectEqualizerPreset: (EqualizerPreset) -> Void
    private let onSetEqualizerOn: (Bool) -> Void
    private let canUseMaxVolumeLimiter: () -> Bool
    private let onSetMaxVolumeLimiter: (Bool) -> Void
    private let canUseVoicePrompt: () -> Bool
    private let onSetVoicePrompt: (Bool) -> Void
    private let todayListeningSeconds: () -> TimeInterval
    private let onIslandSettingsChanged: () -> Void

    private let silhouette = NotchSilhouetteView(frame: .zero)
    private var hosting: NSHostingView<NotchView>!

    /// Owner spec, 2026-10-25 (reverted same day): dragging the island onto the notch used to
    /// magnetically fuse it into the Notch-mode bar, then un-fuse on drag-out. Removed — "remove
    /// the drag to notch feature, let's just set it from the settings": whether a notched display
    /// renders the fused bar or the plain draggable pill is purely `IslandSettings.
    /// notchAttachmentMode(forDisplayUUID:)` (`baseGeometry(for:measurements:)`'s own doc comment
    /// on how that already zeroes `cameraWidth`/`safeAreaTop` for Island mode) — no drag-driven
    /// state needed on top of it.
    private var geometry: IslandGeometry
    /// The resolved display's visibleFrame (excludes the menu bar and, where applicable, the
    /// Dock) — design/DESIGN_GUIDE.md §6: bottom/left/right placement all key off this, not the
    /// raw screen frame, so a bottom dock naturally sits above the Dock.
    private var visibleFrame: CGRect
    private var currentDisplayUUID: String?
    private var edge: DockEdge
    /// Points from the middle of `edge`, already clamped — design/DESIGN_GUIDE.md §6: "centred
    /// along its edge unless dragged."
    private var offset: CGFloat
    /// Whether the island is currently docked to `edge` or freely placed at `freeCenter`. Set by
    /// `handleDragEnd()` depending on how far the drag ended from the nearest screen edge —
    /// dragging is the only way to change this now; Island Settings no longer has its own edge
    /// picker (removed: it could only ever reach a subset of what dragging already covers, and
    /// showed a "distance from edge" number that meant nothing while free-floating).
    private var isFreePositioned: Bool
    /// The island's own logical center point (screen coordinates) while `isFreePositioned` —
    /// both the collapsed pill and the expanded card are centered on this same point, so the
    /// card grows outward around wherever the pill was dropped rather than flush against an edge.
    private var freeCenter: CGPoint
    /// Non-nil when docked flush into a screen corner rather than a plain `edge` — a distinct
    /// third placement mode (free / edge / corner), set by `handleDragEnd()` when a drop lands
    /// close enough to where two edges meet, or restored from `IslandSettings` here/in
    /// `reposition()`. Takes priority over `edge` everywhere it matters (`windowFrame(for:)`,
    /// the collapsed silhouette/content) whenever it's non-nil; `dockToEdge`/`settleFreePositioned`
    /// clear it back to nil the moment the island docks to a plain edge or goes free again.
    private var dockedCorner: ScreenCorner?
    /// How close a drag has to end to a screen edge (measured from the pill's own facing side) to
    /// dock there instead of settling into free placement. Deliberately tight — a docked pill
    /// always sits exactly `IslandSettings.edgeMargin(for:)` (a fixed constant, default 20) from
    /// its edge, never wherever it was actually dropped on that axis; a loose capture zone here
    /// (56 was tried first) meant almost any drop anywhere near the top or bottom snapped into
    /// that fixed distance, making it impossible to leave the island sitting somewhere of your own
    /// choosing near an edge — it kept visibly jumping back to the same fixed spot instead of
    /// staying put. 12 only catches a drop that's essentially flush against the edge already (a
    /// deliberate "dock it" gesture), leaving every other drop, including ones quite close to an
    /// edge, exactly where it was released.
    private static let edgeSnapDistance: CGFloat = 12
    /// Corner docking's own, more generous capture zone — deliberately much looser than
    /// `edgeSnapDistance`. A single-edge catch only ever has to measure one axis close to 0; a
    /// corner catch (`DockPlacement.nearestCorner`) needs *both* axes close to 0 at the same
    /// instant, which is a much harder target to hit by hand at `edgeSnapDistance`'s own tight
    /// 12pt — real-world drags kept landing just outside it on one axis or the other and silently
    /// falling through to a plain single-edge dock instead, even when the drop clearly looked
    /// "in the corner."
    private static let cornerSnapDistance: CGFloat = 48
    /// `collapsedSize(for:geometry:)`/`collapsedGap(edge:geometry:)` both special-case `.top` for
    /// real camera-notch fusion — free placement never fuses with the notch even when dropped
    /// near the top, so call sites pass this instead of the real `edge` whenever
    /// `isFreePositioned` is true. `.bottom` reads oddly here only in isolation; every call site
    /// that uses it ignores `edge` entirely once it isn't `.top` (both functions' own doc
    /// comments), so this is just "any non-top edge," not a claim about which edge it's near.
    ///
    /// Corner docking maps to `.top`/`.bottom` matching the corner's own vertical half (never
    /// `.left`/`.right` — a corner dock's card is always the landscape, 374-wide shape, same as a
    /// plain top/bottom dock) — this still never risks real camera-notch fusion even for a
    /// `topLeft`/`topRight` corner on a notched display: `collapsedSize(for:geometry:)` only
    /// fuses when `geometry.isNotched` is *also* true, and `collapsedGap(edge:geometry:)` reuses
    /// `IslandGeometry.floatingGap`, which already resolves to the same plain floating value on a
    /// non-notched display regardless (`isNotched` — the separate, rendering-facing property —
    /// still independently excludes corner docks from ever rendering flush-fused, on a notched
    /// display or not). Getting this right (not just defaulting everything to `.bottom`) is what
    /// lets ExpandedCard's own `dock`/`CardDock` — threaded straight through from this same
    /// property — orient its cut-out tab to the correct edge of the card for *every* corner, not
    /// just the two bottom ones.
    private var effectiveEdgeForGeometry: DockEdge {
        if isFreePositioned { return .bottom }
        switch dockedCorner {
        case .topLeft, .topRight: return .top
        case .bottomLeft, .bottomRight: return .bottom
        case nil: return edge
        }
    }

    private var currentSize: CGSize
    /// Bumped on every present() call; a stale completion whose generation no longer matches is
    /// dropped instead of applying its (now outdated) frame/content, which is what let a
    /// superseded transition leave the window sized for one state while content rendered for
    /// another — an oversized, seemingly empty shape.
    private var presentGeneration = 0

    private var menuBarMeasurements = MenuBarMeasurements()
    /// screenParametersChanged's own debounce work item — see its doc comment for why.
    private var pendingRepositionWorkItem: DispatchWorkItem?
    /// Both added only while expanded, removed on collapse (design/DESIGN_GUIDE.md §9.2) — unlike
    /// the screen-edge monitors below, which are about *opening* a floating capsule and have
    /// nothing to do with being expanded.
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?
    private var screenEdgeMonitors: [Any] = []
    private var screenEdgePressed = false
    private var autoCollapseWorkItem: DispatchWorkItem?

    /// Extra transparent room reserved, at rest, around both the pill and the card so their own
    /// shadows/glows (CollapsedPill, ExpandedCard — both reach past their own bounds) aren't
    /// clipped by the window's edge. The expanded card's docked edge stays flush (nothing needs to
    /// render past a flush, notch-fused edge); the margin only goes on the other three sides — see
    /// `restingEnvelopeSize(for:edge:symmetric:)`. The collapsed pill is different: `symmetric`
    /// there, margin on *all four* sides, including the docked one — see that parameter's own doc
    /// comment on `layoutContent`.
    private static let shadowMargin: CGFloat = 40

    /// Inflates `contentSize` for the resting envelope. `symmetric` (the collapsed pill's own
    /// settled state): margin on all four sides, ignoring `edge` entirely. Otherwise (the expanded
    /// card, always): double margin on the two sides perpendicular to `edge` (symmetric on that
    /// axis, since the content is centered along the edge), single margin on the far side along
    /// the docked axis (the near side is flush against the docked edge, so it needs none).
    private static func restingEnvelopeSize(for contentSize: CGSize, edge: DockEdge, symmetric: Bool = false) -> CGSize {
        guard !symmetric else {
            return CGSize(width: contentSize.width + shadowMargin * 2, height: contentSize.height + shadowMargin * 2)
        }
        return edge.isVertical
            ? CGSize(width: contentSize.width + shadowMargin, height: contentSize.height + shadowMargin * 2)
            : CGSize(width: contentSize.width + shadowMargin * 2, height: contentSize.height + shadowMargin)
    }

    /// `restingEnvelopeSize(for:edge:symmetric:)`'s corner-dock counterpart: both axes are flush
    /// against a screen edge at a corner (never "centered along an edge" the way a single-edge
    /// dock's perpendicular axis is), so neither axis ever gets *double* margin the way that
    /// function's non-symmetric branch does — just single margin on the one far side of each axis,
    /// or margin on all four sides (both axes' near *and* far side) for the collapsed quarter-disc's
    /// own hover-scale growth room, same `symmetric` reasoning as the plain-edge pill.
    private static func cornerEnvelopeSize(for contentSize: CGSize, symmetric: Bool) -> CGSize {
        symmetric
            ? CGSize(width: contentSize.width + shadowMargin * 2, height: contentSize.height + shadowMargin * 2)
            : CGSize(width: contentSize.width + shadowMargin, height: contentSize.height + shadowMargin)
    }

    /// Routes to `cornerEnvelopeSize(for:symmetric:)` when corner-docked, `restingEnvelopeSize(for:
    /// edge:symmetric:)` otherwise — the one place every envelope-size call site needs to branch,
    /// so none of them have to know about corner docking individually.
    private func envelopeSize(for contentSize: CGSize, symmetric: Bool) -> CGSize {
        dockedCorner != nil
            ? Self.cornerEnvelopeSize(for: contentSize, symmetric: symmetric)
            : Self.restingEnvelopeSize(for: contentSize, edge: edge, symmetric: symmetric)
    }

    /// ExpandedCard's own fixed size (design/DESIGN_GUIDE.md §4/§10) — a real constant, not a
    /// measurement, and must stay in lockstep with ExpandedCard.cardSize (same reasoning there for
    /// why 500, not a flat 470 — the guide's own "about 470" already allows it, and content
    /// measured out to ~478 against a flat 470). Height is fixed regardless of what the card is
    /// showing (or which dock it's on; only the width differs, horizontal vs. vertical docks), so
    /// there's nothing to measure here. See the git history for why measuring it anyway (the
    /// original approach here, before ExpandedCard had a fixed size) was actively wrong, not just
    /// redundant.
    private static let expandedCardSize = CGSize(width: 374, height: 500)
    private static let expandedCardSizeVertical = CGSize(width: 296, height: 500)

    init(
        headphoneState: HeadphoneState, onSelectNoiseMode: @escaping (CommandableNoiseMode) -> Void,
        isModeVerified: @escaping (CommandableNoiseMode) -> Bool,
        supportsNoiseControl: @escaping () -> Bool,
        onReconnectTapped: @escaping () -> Void,
        onOpenBluetoothSettingsTapped: @escaping () -> Void,
        lastMatchedProfileDisplayName: @escaping () -> String?,
        onPowerOff: @escaping () -> Void,
        canPowerOff: @escaping () -> Bool,
        canUseEqualizer: @escaping () -> Bool,
        onSelectEqualizerPreset: @escaping (EqualizerPreset) -> Void = { _ in },
        onSetEqualizerOn: @escaping (Bool) -> Void = { _ in },
        canUseMaxVolumeLimiter: @escaping () -> Bool = { false },
        onSetMaxVolumeLimiter: @escaping (Bool) -> Void = { _ in },
        canUseVoicePrompt: @escaping () -> Bool = { false },
        onSetVoicePrompt: @escaping (Bool) -> Void = { _ in },
        todayListeningSeconds: @escaping () -> TimeInterval = { 0 },
        onIslandSettingsChanged: @escaping () -> Void = {}
    ) {
        self.headphoneState = headphoneState
        self.onSelectNoiseMode = onSelectNoiseMode
        self.isModeVerified = isModeVerified
        self.supportsNoiseControl = supportsNoiseControl
        self.onReconnectTapped = onReconnectTapped
        self.onOpenBluetoothSettingsTapped = onOpenBluetoothSettingsTapped
        self.lastMatchedProfileDisplayName = lastMatchedProfileDisplayName
        self.onPowerOff = onPowerOff
        self.canPowerOff = canPowerOff
        self.canUseEqualizer = canUseEqualizer
        self.onSelectEqualizerPreset = onSelectEqualizerPreset
        self.onSetEqualizerOn = onSetEqualizerOn
        self.canUseMaxVolumeLimiter = canUseMaxVolumeLimiter
        self.onSetMaxVolumeLimiter = onSetMaxVolumeLimiter
        self.canUseVoicePrompt = canUseVoicePrompt
        self.onSetVoicePrompt = onSetVoicePrompt
        self.todayListeningSeconds = todayListeningSeconds
        self.onIslandSettingsChanged = onIslandSettingsChanged

        let resolution = Self.resolveScreen()
        let screen = resolution.screen
        let initialGeometry = Self.baseGeometry(for: screen, measurements: MenuBarMeasurements())
        self.geometry = initialGeometry
        self.visibleFrame = screen?.visibleFrame ?? initialGeometry.screen
        let uuid = screen?.stableDisplayUUIDString
        self.currentDisplayUUID = uuid
        let resolvedEdge = uuid.map { IslandSettings.dockEdge(forDisplayUUID: $0) } ?? .top
        self.edge = resolvedEdge
        self.offset = uuid.map { IslandSettings.dockOffset(forDisplayUUID: $0, edge: resolvedEdge) } ?? 0
        let resolvedIsFree = uuid.map { IslandSettings.placementMode(forDisplayUUID: $0) == .free } ?? false
        self.isFreePositioned = resolvedIsFree
        let visibleFrameForInit = screen?.visibleFrame ?? initialGeometry.screen
        self.freeCenter = uuid.flatMap { IslandSettings.freePosition(forDisplayUUID: $0) } ?? CGPoint(x: visibleFrameForInit.midX, y: visibleFrameForInit.midY)
        self.dockedCorner = uuid.flatMap { IslandSettings.dockedCorner(forDisplayUUID: $0) }
        // Owner-reported, 2026-10-25: "on relaunch it defaults to island even if the setting is on
        // notch." Notch mode has no placement of its own at all — it's always centered on the real
        // notch — but a previous Island-mode session on this same display (free-positioned, corner-
        // docked, or docked to a non-top edge) still has that placement saved under this display's
        // UUID. `reposition()` already force-resets exactly this the moment it runs (its own doc
        // comment), but that only fires on a later screen-parameter change — at launch, `self`
        // doesn't exist yet to call it, so the window's very first frame was still built from the
        // stale Island-mode placement, rendering as a plain pill even though the setting says
        // Notch. Mirroring that same reset here, against the locals already resolved above, makes
        // the very first launch match the setting immediately instead of needing a screen change
        // (or a drag) to self-correct.
        if initialGeometry.isNotched, !(resolvedIsFree == false && self.dockedCorner == nil && resolvedEdge == .top) {
            self.edge = .top
            self.offset = 0
            self.isFreePositioned = false
            self.dockedCorner = nil
        }
        self.currentSize = Self.collapsedSize(for: (self.isFreePositioned || self.dockedCorner != nil) ? .bottom : self.edge, geometry: initialGeometry)

        super.init(
            contentRect: .zero, // real frame set via setFrame(_:display:) below, once contentView/silhouette exist.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        Self.logDisplayResolution(resolution, logger: logger)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.normalLevel
        collectionBehavior = Self.overlayCollectionBehavior
        isMovable = false
        isReleasedWhenClosed = false
        // NSPanel (unlike plain NSWindow) defaults this to `true` — without overriding it, this
        // panel auto-hid itself every time the user switched to a different app (the app
        // resigning active status), then reappeared once something reactivated it: the "blink on
        // switching windows." The island has to stay visible across every app switch, same as any
        // other persistent menu-bar accessory — it's never supposed to behave like a document
        // window that hides along with its owning app.
        hidesOnDeactivate = false
        // A separate blink, specific to switching desktop Spaces / Mission Control (not app
        // switching — `hidesOnDeactivate` above doesn't touch this): `.canJoinAllSpaces` windows
        // get re-composited fresh into each Space by the WindowServer during the switch
        // animation, and without this, AppKit's own default per-window transition (meant for
        // ordinary document windows being shown/hidden) competes with that re-compositing and
        // reads as a visible flash mid-transition. `.none` tells AppKit this panel never needs — or
        // wants — its own animation layered on top of anything the system is already doing to it.
        animationBehavior = .none

        hosting = NSHostingView(
            rootView: NotchView(
                state: headphoneState, uiState: uiState,
                // The pill's own natural size for the current edge — NOT `currentSize`, which
                // `present()` mutates to the *target* size immediately when a transition starts,
                // well before `uiState.isExpanded` itself flips. If anything else triggers a
                // SwiftUI re-render of NotchView in that window (any other @Observable state
                // changing at the same moment), the outgoing CollapsedPill would re-measure
                // itself against the already-mutated, now-expanded `currentSize` instead of its
                // own real size — sizing itself as if it were the card it's being replaced by.
                collapsedSize: { [weak self] in
                    self.map { Self.collapsedSize(for: $0.effectiveEdgeForGeometry, geometry: $0.geometry) } ?? .zero
                },
                onSelectNoiseMode: onSelectNoiseMode, isModeVerified: isModeVerified,
                supportsNoiseControl: supportsNoiseControl,
                isNotched: { [weak self] in self?.isNotched ?? false },
                hasRealNotchOnCurrentDisplay: {
                    guard let screen = Self.resolveScreen().screen else { return false }
                    return Self.hasRealNotch(on: screen)
                },
                currentDisplayUUID: { [weak self] in self?.currentDisplayUUID },
                dockEdge: { [weak self] in self?.effectiveEdgeForGeometry ?? .top },
                dockedCorner: { [weak self] in self?.dockedCorner },
                freeFloatingNotch: { [weak self] in self?.freeFloatingNotch() },
                onCollapseTabTapped: { [weak self] in self?.handleTabTap() },
                onReconnectTapped: onReconnectTapped, onOpenBluetoothSettingsTapped: onOpenBluetoothSettingsTapped,
                lastMatchedProfileDisplayName: lastMatchedProfileDisplayName,
                onPowerOff: onPowerOff, canPowerOff: canPowerOff,
                canUseEqualizer: canUseEqualizer,
                onSelectEqualizerPreset: onSelectEqualizerPreset, onSetEqualizerOn: onSetEqualizerOn,
                canUseMaxVolumeLimiter: canUseMaxVolumeLimiter, onSetMaxVolumeLimiter: onSetMaxVolumeLimiter,
                canUseVoicePrompt: canUseVoicePrompt, onSetVoicePrompt: onSetVoicePrompt,
                todayListeningSeconds: todayListeningSeconds,
                onIslandSettingsChanged: onIslandSettingsChanged
            )
        )
        // NSHostingView does not clip its own content to its frame by default. `hosting` itself
        // stays sized to the pill/card's own exact content size (unchanged, still positioned by
        // the same origin math below) — the surrounding `container` is the one sized to the
        // margined envelope, so CollapsedPill/ExpandedCard's own shadows have real window room to
        // bleed into. masksToBounds stays off deliberately: it would clip that intentional
        // overflow right back off, same as it would an oversized estimate. Set explicitly, not
        // left to CALayer's own default — this is the one thing standing between a correctly
        // sized/positioned content frame (the window and hosting-frame math are each independently
        // verified) and that content actually being visible at full size.
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = false

        // NotchPanel always starts collapsed (currentSize above), so this initial envelope/layout
        // is the collapsed pill's own settled state — symmetric: true throughout, same as every
        // other settling call site (present()'s completion, presentImmediately()).
        let initialEnvelope = envelopeSize(for: currentSize, symmetric: true)
        let container = NSView(frame: NSRect(origin: .zero, size: initialEnvelope))
        container.wantsLayer = true
        container.layer?.masksToBounds = false
        container.addSubview(silhouette)
        container.addSubview(hosting)
        contentView = container

        silhouette.onTap = { [weak self] in self?.handleTap() }
        // Owner spec, 2026-10-25: "on notch, it should sit there and not be able to be moved" —
        // the fused NotchExtensionBar is permanently centered on the real notch; a drag starting
        // on it would otherwise still run (this gate only ever checked `isExpanded`), relocating
        // the window via `clampedDragOrigin`/`handleDragEnd` directly — neither of those goes
        // through `windowFrame(for:)`'s own notch centering, so a drag could actually move it away
        // from the notch even though every *layout* recompute would snap it straight back.
        silhouette.canDrag = { [weak self] in !(self?.uiState.isExpanded ?? true) && !(self?.isNotched ?? false) }
        // Re-enabled: a `log stream` capture with this disabled showed drops landing hundreds to
        // thousands of points off-screen, producing raw `offset`/`freeCenter` values so extreme
        // that the collapsed pill's and expanded card's own per-size offset clamps (windowFrame
        // (for:)'s own doc comment) disagreed by over 200pt for the same stored offset — that
        // mismatch, not a bug in the clamping logic itself, was the actual cause of the tray
        // opening displaced from the pill. It's also what made landing flush in a screen corner
        // (DockPlacement.nearestCorner's own doc comment) unreliable: corner distance only reads
        // as "close" when the drop is genuinely, physically flush, which an unclamped drag rarely
        // produces by hand.
        silhouette.clampOrigin = { [weak self] rawOrigin in self?.clampedDragOrigin(rawOrigin) ?? rawOrigin }
        silhouette.onDragEnd = { [weak self] in self?.handleDragEnd() }
        silhouette.dockEdge = edge

        layoutContent(for: currentSize, envelopeSize: initialEnvelope, symmetric: true)
        setFrame(windowFrame(for: initialEnvelope, symmetric: true), display: false)
        logger.info("NotchPanel created. frame=\(NSStringFromRect(self.frame), privacy: .public) edge=\(self.edge.rawValue, privacy: .public)")
        silhouette.setFillColor(currentSilhouetteFillColor())
        // Give the silhouette an initial path immediately — otherwise it stays empty (zero
        // frame) until the first expand/collapse transition ever runs.
        let initialGap = Self.collapsedGap(edge: effectiveEdgeForGeometry, geometry: initialGeometry)
        silhouette.resize(
            to: currentSize, from: currentSize,
            startGap: initialGap, targetGap: initialGap,
            envelopeSize: initialEnvelope, symmetric: true, reduceMotion: true, completion: {}
        )

        syncScreenEdgeMonitors()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        // The blink the owner actually reported — switching desktop Spaces (3-finger swipe /
        // Ctrl+arrow) and completing a Cmd+Tab app switch — is neither `hidesOnDeactivate` nor
        // `animationBehavior` (both already set above; neither resolved it). It's a known,
        // documented WindowServer quirk for an always-visible `.canJoinAllSpaces` overlay panel:
        // during these transitions the compositor can momentarily mis-order or re-composite it,
        // reading as a flash. There's no single NSWindow property that reliably prevents that —
        // the practical mitigation other menu-bar overlay apps use is re-asserting the window to
        // front the instant the transition actually completes, rather than trusting the
        // WindowServer's own ordering to stay correct through it.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reassertFrontAfterTransition),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reassertFrontAfterTransition),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    @objc private func reassertFrontAfterTransition() {
        guard isVisible else { return }
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .unknown }

    deinit {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let escKeyMonitor { NSEvent.removeMonitor(escKeyMonitor) }
        screenEdgeMonitors.forEach(NSEvent.removeMonitor)
    }

    /// The pill/card's own fill (Theme.Semantic.pillBackground / cardFrame: white in light theme,
    /// black in dark) mirrored for the native silhouette, which has no SwiftUI/asset-catalog
    /// access of its own — set right before every resize so the native layer never shows the
    /// stale default while the SwiftUI content is still hidden mid-animation.
    private func currentSilhouetteFillColor() -> NSColor {
        if isNotched { return .black }
        return effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
    }

    // MARK: - Visibility

    func setVisible(_ visible: Bool) {
        if visible {
            orderFrontRegardless()
        } else {
            orderOut(nil)
        }
    }

    // MARK: - Classic connection hooks

    func handleClassicConnected() {
        setVisible(true)
        // design/DESIGN_GUIDE.md: auto-expand-on-connect is an opt-in Island Settings toggle,
        // default off — connecting no longer expands the card unless the user asked for that.
        if IslandSettings.autoExpandOnConnect {
            expand()
            scheduleAutoCollapse(after: 4)
        }
    }

    /// Deliberately does not collapse. design/DESIGN_GUIDE.md §9.5 "Connected to disconnected" is
    /// a plain crossfade *within* the still-open card, not a forced close — CardConditionResolver
    /// already resolves `.noDevice` the instant HeadphoneState.connection flips, so ExpandedCard
    /// (if currently expanded) re-renders itself into the "No headphones" layout on its own; if
    /// already collapsed, there's nothing to do here at all. Force-collapsing used to snap the
    /// card shut out from under the user the moment the headphones powered off, instead of letting
    /// them see the no-device state in place.
    func handleClassicDisconnected() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
    }

    // MARK: - Settings changed (size/silhouette/fits/outline/display/edge)

    // Owner spec, 2026-10-24: both the collapsed state (NotchExtensionBar — a fused two-wing bar)
    // and the expanded card now render flush/attached to a real notch, centered on it, so this no
    // longer needs to distinguish collapsed from expanded the way an earlier (now-replaced)
    // beside-the-notch-circle version of the collapsed state did.
    //
    var isNotched: Bool { !isFreePositioned && dockedCorner == nil && edge == .top && geometry.isNotched }

    /// The fallback NSStatusItem menu's own "Island Settings…" item. Island Settings no longer has
    /// its own window (owner request, 2026-10-22: "the external island setting is still
    /// implemented, can you remove it... the only island setting we have is on the island") — this
    /// expands the tray (same as a hover/click would) and bumps the token so NotchView/ExpandedCard
    /// open straight to the in-tray Island Settings sheet, skipping the picker. See
    /// NotchUIState.islandSettingsRequestToken's own doc comment for why a token, not a direct call.
    func requestOpenIslandSettings() {
        // The bump has to happen *after* the card is actually mounted (expand()'s completion, not
        // immediately after calling it) — ExpandedCard is torn down/rebuilt on every collapse/
        // expand cycle (StaggerIn's own doc comment), so a token change that lands before the new
        // instance's `.onChange` subscription exists would be silently missed. expand() always
        // calls its completion, whether it actually had to present (currently collapsed) or was
        // already expanded (its own early-return still calls completion()), so this fires reliably
        // either way.
        expand { [weak self] in
            self?.uiState.islandSettingsRequestToken += 1
        }
    }

    /// The fallback NSStatusItem menu's own "Report a Bug / Suggest a Feature…" item — same
    /// token-bump pattern as requestOpenIslandSettings() above, and for the same reason.
    func requestOpenFeedback() {
        uiState.feedbackRequestToken += 1
    }

    func settingsDidChange() {
        // Forced, not a plain reposition(): a margin change on bottom/left/right isn't visible to
        // reposition()'s own "did anything actually change" guard at all — IslandSettings.edgeMargin
        // is read live inside windowFrame(for:), not stored on `geometry`/`currentSize`, the only
        // two things that guard compares. Without forcing it, that guard saw no difference and
        // bailed out before ever calling presentImmediately(), so the window silently never moved.
        reposition(force: true)
    }

    // MARK: - Expand / collapse

    private func expand(suppressPhotoFlight: Bool = false, completion: @escaping () -> Void = {}) {
        guard !uiState.isExpanded else { completion(); return }
        present(expanded: true, suppressPhotoFlight: suppressPhotoFlight, completion: completion)
        installExpandedMonitors()
    }

    private func collapse(suppressPhotoFlight: Bool = false, completion: @escaping () -> Void = {}) {
        guard uiState.isExpanded else { completion(); return }
        present(expanded: false, suppressPhotoFlight: suppressPhotoFlight, completion: completion)
        removeExpandedMonitors()
    }

    private func handleTap() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        if uiState.isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    /// The expanded card's own cut-out tab (design/DESIGN_GUIDE.md §4) always collapses — unlike
    /// `handleTap`, which toggles, the tab is only ever visible/tappable while already expanded.
    private func handleTabTap() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        collapse()
    }

    private func scheduleAutoCollapse(after seconds: TimeInterval) {
        autoCollapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.collapse() }
        autoCollapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: - Click to open/close (design/DESIGN_GUIDE.md §9.2)
    //
    // A click on the pill itself opens it (NotchSilhouetteView.onTap -> handleTap, always
    // installed). Collapsing happens three ways: a click on the tab (handleTabTap, always
    // installed — the tab only exists once expanded anyway), a click outside the card, or Esc —
    // the last two are both global monitors, installed only while expanded and removed on
    // collapse, so there's no standing global monitor at all while collapsed.

    private func installExpandedMonitors() {
        guard outsideClickMonitor == nil else { return }
        // A *global* monitor only ever reports events in other apps' windows, never this one's
        // own — "clicks inside the card never collapse it" falls out of that for free, the same
        // way it always has.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.handleOutsideClick() }
        }
        escKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // Esc
            Task { @MainActor in self?.handleEscKey() }
        }
    }

    private func removeExpandedMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        if let escKeyMonitor { NSEvent.removeMonitor(escKeyMonitor) }
        escKeyMonitor = nil
    }

    private func handleOutsideClick() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        collapse()
    }

    private func handleEscKey() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        collapse()
    }

    // MARK: - Free drag anywhere on screen, snapping to an edge on release

    /// Called on every single `mouseDragged` tick (see `NotchSilhouetteView.mouseDragged`'s own
    /// doc comment for why this has to be a live, per-tick clamp rather than a one-shot
    /// correction after the fact). `rawOrigin` is the window's own next unclamped *envelope*
    /// origin — the drag only ever starts while collapsed (`canDrag` forbids it otherwise), so the
    /// envelope is always the small pill's `currentSize` padded symmetrically by `shadowMargin` on
    /// every side (same math as `restingEnvelopeSize(for:edge:symmetric: true)`). Clamping
    /// happens against the actual visible content rect, not the padded envelope itself, for the
    /// same reason `handleDragEnd()` below measures distances against content, not envelope: the
    /// envelope legitimately extends past the real screen edge by design whenever the configured
    /// edge margin is smaller than `shadowMargin` (the default always is), so clamping the
    /// envelope directly would fight that and drag the visible pill away from the real edge.
    ///
    /// Resolves the active screen fresh from `rawOrigin` itself (geometric overlap, same
    /// `resolveScreen(overlapping:)` used everywhere else — never `self.screen`/`NSScreen.main`,
    /// which don't reliably track this non-key panel's real screen), so a drag that crosses from
    /// one display onto another stays correctly bounded by whichever display it's actually over
    /// at that instant, not whichever one the drag started on.
    private func clampedDragOrigin(_ rawOrigin: CGPoint) -> CGPoint {
        let contentSize = currentSize
        let rawContentOrigin = CGPoint(x: rawOrigin.x + Self.shadowMargin, y: rawOrigin.y + Self.shadowMargin)
        let rawContentFrame = CGRect(origin: rawContentOrigin, size: contentSize)
        let activeVisibleFrame = Self.resolveScreen(overlapping: rawContentFrame)?.visibleFrame ?? visibleFrame

        let clampedContentOrigin = CGPoint(
            x: min(max(rawContentOrigin.x, activeVisibleFrame.minX), activeVisibleFrame.maxX - contentSize.width),
            y: min(max(rawContentOrigin.y, activeVisibleFrame.minY), activeVisibleFrame.maxY - contentSize.height)
        )
        return CGPoint(x: clampedContentOrigin.x - Self.shadowMargin, y: clampedContentOrigin.y - Self.shadowMargin)
    }

    /// Mirrors `clampedDragOrigin(_:)` above, but in content-rect terms against whichever screen
    /// `frame` (the actual window, post-drag) now overlaps most — used both by the live per-tick
    /// clamp during the drag and, here, by the one-shot docking decision once it ends.
    ///
    /// By the time this fires, `NotchSilhouetteView.mouseDragged` has already moved the window to
    /// its final dropped position (each tick already clamped live via `clampedDragOrigin(_:)`) —
    /// all that's left is deciding whether that drop counts as docking to the nearest edge or
    /// settling into free placement, and persisting the result.
    ///
    /// Decides, once a drag actually ends, whether the island docks to the nearest screen edge
    /// (close enough — `Self.edgeSnapDistance`) or settles into free placement at wherever it was
    /// dropped. Either way the result is persisted immediately, same as every other placement
    /// change in this file.
    private func handleDragEnd() {
        // The drag may have crossed onto a different physical display than the one
        // `visibleFrame`/`currentDisplayUUID` were last resolved for — `reposition()` resolves
        // against "whichever screen should host the menu bar companion" (IslandSettings.
        // chosenDisplayUUID or wherever the menu bar currently is), not "whichever screen the pill
        // actually just landed on." Refresh both from the window's own real position before
        // computing anything below, or every distance/clamp here would still measure against the
        // *old* screen's bounds.
        //
        // Also persist this as the new `chosenDisplayUUID` — not just `currentDisplayUUID` here in
        // memory. Without this, `currentDisplayUUID` and the saved display preference could
        // disagree the moment a drag lands on a display other than the previously-chosen one: any
        // later `reposition()` (fired by `screenParametersChanged`, which reacts to routine screen-
        // parameter notifications, not only an actual monitor being connected/disconnected) always
        // re-resolves against the *saved* preference, found that it no longer matched
        // `currentDisplayUUID`, and reloaded `offset`/`edge` fresh from `IslandSettings` for that
        // other (stale-preference) display — 0 (centered) if nothing had ever been saved there —
        // discarding wherever the drop had actually just placed it. Explicitly dragging the island
        // onto a display is as clear a signal of the user's intended display as the Island
        // Settings picker itself.
        if let droppedScreen = Self.resolveScreen(overlapping: frame) {
            visibleFrame = droppedScreen.visibleFrame
            currentDisplayUUID = droppedScreen.stableDisplayUUIDString
            IslandSettings.chosenDisplayUUID = currentDisplayUUID
        }

        // Deliberately NOT clamping `frame` itself here. `frame` is the padded *envelope*
        // (currentSize inflated by `shadowMargin`, 40pt a side, for shadow/glow bleed room) —
        // when the configured edge margin is smaller than that padding (the 20pt default always
        // is), the envelope's own legitimate resting position already sits past the screen edge
        // on purpose (windowFrame(for:)'s own `symmetric` compensation relies on exactly this, to
        // keep the *visible* pill at the correct inset while the invisible backing-store room
        // still has somewhere to go). A blunt clamp on `frame` here was fighting that and forcing
        // the envelope's edge to land exactly on the screen's real edge on almost every drop near
        // the top or bottom — which made `distanceToBottom`/`distanceToTop` read as 0 nearly every
        // time, which always counted as "close enough to dock," which is exactly what read as
        // "it keeps jumping back to a fixed, docked position" regardless of where it was dropped.
        // Measuring against the actual visible content (the small circle, centered within the
        // envelope) instead of the envelope's own padded bounds is what the user visually
        // perceives as "how close to the edge," and has none of this false-positive problem.
        let droppedFrame = frame
        let contentSize = currentSize
        let contentFrame = CGRect(
            x: droppedFrame.midX - contentSize.width / 2, y: droppedFrame.midY - contentSize.height / 2,
            width: contentSize.width, height: contentSize.height
        )
        let center = CGPoint(x: droppedFrame.midX, y: droppedFrame.midY)

        // Checked before the single-edge distances just below, and wins if it matches: a drop
        // close enough to where two edges actually meet docks into that corner, not just the
        // nearer of the two edges (which, before corner docking existed, is what overflowed past
        // the far one — NotchPanel.windowFrame(for:)'s own `.top` case doc comment has the "part
        // of it is hidden" symptom this fixed).
        if let corner = DockPlacement.nearestCorner(contentFrame: contentFrame, visibleFrame: visibleFrame, snapDistance: Self.cornerSnapDistance) {
            dockToCorner(corner)
            return
        }

        let distanceToTop = visibleFrame.maxY - contentFrame.maxY
        let distanceToBottom = contentFrame.minY - visibleFrame.minY
        let distanceToLeft = contentFrame.minX - visibleFrame.minX
        let distanceToRight = visibleFrame.maxX - contentFrame.maxX
        let distances: [(DockEdge, CGFloat)] = [
            (.top, distanceToTop), (.bottom, distanceToBottom), (.left, distanceToLeft), (.right, distanceToRight)
        ]
        let nearest = distances.min { $0.1 < $1.1 }
        if let nearest, nearest.1 <= Self.edgeSnapDistance {
            dockToEdge(nearest.0, nearCenter: center)
        } else {
            settleFreePositioned(atCenter: center)
        }
    }

    /// Docks the island flush into `corner` — unlike `dockToEdge`, there's no `nearCenter`-derived
    /// offset to compute at all (`cornerFrame`'s own doc comment): the corner itself is the whole
    /// placement, so docking here is always exact, never approximate-then-clamped the way an edge
    /// offset is.
    private func dockToCorner(_ corner: ScreenCorner) {
        dockedCorner = corner
        isFreePositioned = false
        if let currentDisplayUUID {
            IslandSettings.setPlacementMode(.edge, forDisplayUUID: currentDisplayUUID)
            IslandSettings.setDockedCorner(corner, forDisplayUUID: currentDisplayUUID)
        }
        currentSize = Self.collapsedSize(for: effectiveEdgeForGeometry, geometry: geometry)
        uiState.geometryVersion += 1
        presentImmediately(expanded: false)
    }

    /// Docks the island to `newEdge`, computing the offset from `nearCenter` so it ends up as
    /// close as possible to where it was actually dropped (clamped, same as every other offset
    /// change) rather than snapping back to the edge's own middle.
    private func dockToEdge(_ newEdge: DockEdge, nearCenter: CGPoint) {
        let rawOffset = newEdge.isVertical ? (nearCenter.y - visibleFrame.midY) : (nearCenter.x - visibleFrame.midX)
        edge = newEdge
        isFreePositioned = false
        dockedCorner = nil
        silhouette.dockEdge = newEdge
        // Clamped against the small collapsed pill's own range only, not intersected with the
        // expanded card's — windowFrame(for:)'s own doc comment covers the expanded case
        // separately now (clamped fresh, live, against whichever size it's actually resolving),
        // so the *persisted*, resting offset only has to keep the pill itself on screen. Clamping
        // it against the card's own (much tighter) valid range here instead pulled the resting
        // pill dramatically toward the edge's middle whenever it was dropped well away from
        // center — a visible, large jump up/down (or left/right) from wherever it was dropped.
        offset = DockPlacement.clampedOffset(
            rawOffset, collapsedSize: currentSize, expandedSize: currentSize, edge: newEdge, visibleFrame: visibleFrame
        )
        if let currentDisplayUUID {
            IslandSettings.setPlacementMode(.edge, forDisplayUUID: currentDisplayUUID)
            IslandSettings.setDockEdge(newEdge, forDisplayUUID: currentDisplayUUID)
            IslandSettings.setDockOffset(offset, forDisplayUUID: currentDisplayUUID, edge: newEdge)
            IslandSettings.setDockedCorner(nil, forDisplayUUID: currentDisplayUUID)
        }
        uiState.geometryVersion += 1
        presentImmediately(expanded: false)
    }

    /// Settles into free placement at `center`, clamped so the pill can never end up fully off
    /// whatever's left of the visible screen area.
    private func settleFreePositioned(atCenter center: CGPoint) {
        // Clamped against the small *collapsed* pill's own footprint, not the much larger
        // expanded card's — windowFrame(for:)'s own doc comment covers the expanded case
        // separately now (clamped fresh, live, against whichever size is actually being resolved
        // at the time), so this only has to guarantee the *resting*, collapsed position itself is
        // on screen. Clamping by the card's footprint here instead pushed any pill dropped within
        // ~150-190pt of an edge inward to that same fixed distance every time, regardless of
        // where it was actually dropped — the opposite of "stay where I put it."
        let halfWidth = currentSize.width / 2
        let halfHeight = currentSize.height / 2
        let clampedCenter = CGPoint(
            x: min(max(center.x, visibleFrame.minX + halfWidth), visibleFrame.maxX - halfWidth),
            y: min(max(center.y, visibleFrame.minY + halfHeight), visibleFrame.maxY - halfHeight)
        )
        isFreePositioned = true
        freeCenter = clampedCenter
        dockedCorner = nil
        if let currentDisplayUUID {
            IslandSettings.setPlacementMode(.free, forDisplayUUID: currentDisplayUUID)
            IslandSettings.setFreePosition(clampedCenter, forDisplayUUID: currentDisplayUUID)
            IslandSettings.setDockedCorner(nil, forDisplayUUID: currentDisplayUUID)
        }
        uiState.geometryVersion += 1
        presentImmediately(expanded: false)
    }

    // MARK: - Click outside collapses (global monitor); screen-edge strip above a capsule opens it

    /// The thin strip of real menu bar directly above a floating top capsule isn't part of our
    /// own window, so a normal click there never reaches us — only a top capsule needs this; the
    /// other three edges have no such gap to bridge.
    private var screenEdgeClickArea: CGRect? {
        guard !isFreePositioned, edge == .top, let gap = geometry.floatingGap, gap > 0, !uiState.isExpanded, isVisible, !ignoresMouseEvents else { return nil }
        // Only ever reached while collapsed (the guard above) — symmetric: true, matching every
        // other collapsed-state windowFrame(for:) call, so this strip starts from the real
        // window's actual top edge, not where it would've been under the old flush positioning.
        let islandFrame = windowFrame(for: currentSize, symmetric: true)
        return CGRect(x: islandFrame.minX, y: islandFrame.maxY, width: islandFrame.width, height: gap + 2)
    }

    private func syncScreenEdgeMonitors() {
        // Deliberately NOT `.leftMouseDragged` — that used to fire this monitor pair (each
        // hopping through a `Task { @MainActor in ... }`) on *every* drag tick of the island's
        // own pill drag too, competing with that drag's own synchronous window move for
        // main-thread time and reading as the drag stuttering or cutting out partway through.
        // This monitor only ever needs press/release for the thin top-edge click strip
        // (screenEdgeClickArea's own doc comment) — it never needed drag deltas at all.
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        guard screenEdgeMonitors.isEmpty else { return }
        if let token = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            Task { @MainActor in self?.handleScreenEdgeEvent(event) }
        }) { screenEdgeMonitors.append(token) }
        if let token = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            Task { @MainActor in self?.handleScreenEdgeEvent(event) }
            return event
        }) { screenEdgeMonitors.append(token) }
    }

    private func handleScreenEdgeEvent(_ event: NSEvent) {
        guard let area = screenEdgeClickArea else { screenEdgePressed = false; return }
        let point = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            screenEdgePressed = area.contains(point)
        case .leftMouseUp:
            let wasPressed = screenEdgePressed
            screenEdgePressed = false
            if wasPressed, area.contains(point) { expand() }
        default:
            break
        }
    }

    // MARK: - Screen / geometry resolution

    @objc private func screenParametersChanged() {
        // Owner-reported, 2026-10-24: reacting to this notification immediately could read
        // screen.visibleFrame/auxiliaryTopLeftArea/auxiliaryTopRightArea a moment before AppKit had
        // actually settled the new geometry (seen going into/out of a scaled built-in-display
        // resolution), caching a bad menu-bar-height/notch reading for that display that then stuck
        // until the next change. Debounce instead of acting on the first firing — this notification
        // can also fire several times in a burst for one real change (e.g. Spaces + Dock
        // repositioning together), so this also collapses those into a single reposition().
        pendingRepositionWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.reposition() }
        pendingRepositionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func reposition(force: Bool = false) {
        let resolution = Self.resolveScreen()
        Self.logDisplayResolution(resolution, logger: logger)
        guard let screen = resolution.screen else {
            logger.error("reposition(): no display available; keeping current geometry")
            return
        }
        menuBarMeasurements.retainDisplays(NSScreen.screens.map(\.notchDisplayID))
        let next = Self.baseGeometry(for: screen, measurements: menuBarMeasurements)
        let nextVisibleFrame = screen.visibleFrame
        let nextUUID = screen.stableDisplayUUIDString

        // Owner-reported, 2026-10-25: switching Island Settings from Island back to Notch after
        // having dragged the island to a free position elsewhere on screen did nothing until it
        // was dragged back close to the notch first. Cause: `isNotched` (this panel's own computed
        // property) requires `!isFreePositioned && dockedCorner == nil && edge == .top` on top of
        // `geometry.isNotched` — flipping the setting makes `geometry.isNotched` true again
        // immediately, but `isFreePositioned`/`dockedCorner`/`edge` are per-display placement state
        // that `reposition()` otherwise only ever touches when the *display itself* changes (right
        // below), so a stale free/corner/other-edge placement from Island mode silently kept
        // `isNotched` false until something else (a drag) happened to reset them. Notch mode has no
        // placement of its own at all — it's always centered on the real notch — so force this
        // state back to its baseline the instant the geometry says a real notch is active again.
        if next.isNotched, !(isFreePositioned == false && dockedCorner == nil && edge == .top) {
            isFreePositioned = false
            dockedCorner = nil
            edge = .top
            silhouette.dockEdge = edge
        }

        if nextUUID != currentDisplayUUID {
            // A genuinely different physical display — load *that* display's own saved
            // placement rather than carrying over whatever was in memory for the old one.
            currentDisplayUUID = nextUUID
            edge = nextUUID.map { IslandSettings.dockEdge(forDisplayUUID: $0) } ?? .top
            offset = nextUUID.map { IslandSettings.dockOffset(forDisplayUUID: $0, edge: edge) } ?? 0
            isFreePositioned = nextUUID.map { IslandSettings.placementMode(forDisplayUUID: $0) == .free } ?? false
            freeCenter = nextUUID.flatMap { IslandSettings.freePosition(forDisplayUUID: $0) } ?? CGPoint(x: nextVisibleFrame.midX, y: nextVisibleFrame.midY)
            dockedCorner = nextUUID.flatMap { IslandSettings.dockedCorner(forDisplayUUID: $0) }
            silhouette.dockEdge = edge
        }

        // A resolution/Dock change (even on the same display) can push a previously-valid free
        // position outside the new visible area — clamp it back in, same reasoning as the offset
        // re-clamp below.
        if isFreePositioned {
            // The small collapsed pill's own footprint, not the expanded card's — see
            // windowFrame(for:)'s own doc comment: the expanded case now clamps itself fresh,
            // live, against whichever size it's actually resolving, so this only has to keep the
            // *resting* position on screen.
            let freeSize = Self.collapsedSize(for: effectiveEdgeForGeometry, geometry: next)
            let halfWidth = freeSize.width / 2
            let halfHeight = freeSize.height / 2
            freeCenter = CGPoint(
                x: min(max(freeCenter.x, nextVisibleFrame.minX + halfWidth), nextVisibleFrame.maxX - halfWidth),
                y: min(max(freeCenter.y, nextVisibleFrame.minY + halfHeight), nextVisibleFrame.maxY - halfHeight)
            )
        }

        let nextCollapsedSize = Self.collapsedSize(for: effectiveEdgeForGeometry, geometry: next)
        guard force || next != geometry || visibleFrame != nextVisibleFrame
            || currentSize != (uiState.isExpanded ? Self.expandedSize(for: effectiveEdgeForGeometry, geometry: next) : nextCollapsedSize)
        else { return }

        geometry = next
        visibleFrame = nextVisibleFrame
        // A resolution/Dock change can push the current offset out of bounds even though the
        // display itself didn't change — re-clamp (never reset to 0) so a drag the user placed
        // deliberately only moves as little as it has to. Against the collapsed pill's own range
        // only, not the expanded card's — windowFrame(for:)'s own doc comment covers the expanded
        // case separately, clamped fresh against whichever size it's actually resolving.
        offset = DockPlacement.clampedOffset(offset, collapsedSize: nextCollapsedSize, expandedSize: nextCollapsedSize, edge: edge, visibleFrame: nextVisibleFrame)
        syncScreenEdgeMonitors()
        // See NotchUIState.geometryVersion's own doc comment — a display/resolution/Dock change
        // can change `edge` (a different display's own saved edge) or `geometry` (notch presence,
        // capsule sizing) without necessarily changing isExpanded, which alone wouldn't give
        // SwiftUI any reason to re-evaluate CollapsedPill/ExpandedCard for the new state.
        uiState.geometryVersion += 1
        presentImmediately(expanded: uiState.isExpanded)
    }

    /// Resolves which physical display `rect` actually sits on by direct geometric overlap
    /// against every connected `NSScreen`, picking whichever has the most overlapping area —
    /// robust even when `rect` straddles the seam between two displays, unlike testing a single
    /// point. Deliberately never consults `self.screen` or `NSScreen.main`: both are documented
    /// to track whichever screen holds the *key* window, and `NotchPanel.canBecomeKey` is
    /// hardcoded to `false` (the island must never steal focus) — there's no guarantee either
    /// property tracks this specific window's own real position at all, let alone live during a
    /// drag, which is exactly the kind of mismatch that read as the drop snapping to a boundary
    /// from a completely different (and wrong) screen's bounds.
    private static func resolveScreen(overlapping rect: CGRect) -> NSScreen? {
        func overlapArea(_ screen: NSScreen) -> CGFloat {
            let intersection = screen.frame.intersection(rect)
            return max(0, intersection.width) * max(0, intersection.height)
        }
        return NSScreen.screens.max { overlapArea($0) < overlapArea($1) }
    }

    private struct ScreenResolution {
        let screen: NSScreen?
        let didFallBack: Bool
        let chosenUUID: String?
    }

    /// Picks the display to place the island on, via DisplayResolver's pure fallback logic (see
    /// its own doc comment) rather than NSScreen-matching inline here, so the fallback decision
    /// itself is unit-testable.
    private static func resolveScreen() -> ScreenResolution {
        let chosenUUID = IslandSettings.chosenDisplayUUID
        let screens = NSScreen.screens
        let candidates = screens.map { DisplayResolver.Candidate(uuid: $0.stableDisplayUUIDString, frame: $0.frame) }
        switch DisplayResolver.resolve(chosenUUID: chosenUUID, candidates: candidates) {
        case .chosen(let index):
            return ScreenResolution(screen: screens[index], didFallBack: false, chosenUUID: chosenUUID)
        case .fallback(let index):
            let screen = index.map { screens[$0] }
            return ScreenResolution(screen: screen, didFallBack: chosenUUID != nil, chosenUUID: chosenUUID)
        }
    }

    private static func logDisplayResolution(_ resolution: ScreenResolution, logger: Logger) {
        if resolution.didFallBack, let chosenUUID = resolution.chosenUUID {
            logger.info(
                "Saved display \(chosenUUID, privacy: .public) not found among connected displays (or had an empty frame); falling back to the default display"
            )
        }
        if let screen = resolution.screen {
            logger.info(
                "Island placed on display uuid=\(screen.stableDisplayUUIDString ?? "unknown", privacy: .public) frame=\(NSStringFromRect(screen.frame), privacy: .public)"
            )
        } else {
            logger.error("No display available to place the island on")
        }
    }

    /// The raw, hardware-only "does this screen have a real camera notch" reading — never affected
    /// by IslandSettings.notchAttachmentMode (that's applied afterward, only inside
    /// `baseGeometry(for:measurements:)`). Exposed via `hasRealNotch(on:)` so Island Settings can
    /// decide whether to even show the Notch/Island choice, independent of whichever one is
    /// currently selected.
    private static func rawNotchInfo(for screen: NSScreen) -> (cameraWidth: CGFloat, safeAreaTop: CGFloat) {
        // Owner-reported, 2026-10-24: on the built-in display at a scaled ("more space", non-
        // native) resolution — e.g. 1470x956 — auxiliaryTopLeftArea/auxiliaryTopRightArea can
        // report rects that don't match the coordinate space screen.frame is currently expressed
        // in (that mismatch only ever showed up at a non-native scaled resolution in testing; the
        // same Mac's external display, which never runs scaled, never hit it). A bogus cameraWidth
        // flips IslandGeometry.isNotched true on a display that isn't actually presenting a real
        // camera notch right now, which forces floatingDrop to 0 and hangs the island flush using
        // the notch-sized cameraHeight instead of the user's own top margin — reading as the island
        // dropping well below the real menu bar, floating over window content. A real notch is a
        // few hundred points wide at most on any Mac display; bound cameraWidth to a width a real
        // notch could plausibly be (and require it sit near the screen's own top edge) before
        // trusting it, rather than accepting whatever the API hands back unchecked.
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
            left.maxY > screen.frame.maxY - 64, right.maxY > screen.frame.maxY - 64 {
            let rawWidth = right.minX - left.maxX
            cameraWidth = (rawWidth.isFinite && rawWidth > 0 && rawWidth <= min(320, screen.frame.width * 0.4))
                ? rawWidth : 0
        } else {
            cameraWidth = 0
        }
        return (cameraWidth, screen.safeAreaInsets.top)
    }

    /// Hardware-only, setting-independent — IslandSettingsControls' own "Notch/Island" picker row
    /// uses this to decide whether to show itself at all.
    static func hasRealNotch(on screen: NSScreen) -> Bool {
        let raw = rawNotchInfo(for: screen)
        return raw.safeAreaTop.isFinite && raw.safeAreaTop > 0 && raw.safeAreaTop <= 64
            && raw.cameraWidth.isFinite && raw.cameraWidth > 0
    }

    private static func baseGeometry(for screen: NSScreen?, measurements: MenuBarMeasurements) -> IslandGeometry {
        guard let screen else {
            return IslandGeometry(screen: .zero, safeAreaTop: 0, cameraWidth: 0)
        }
        var measurements = measurements
        let raw = rawNotchInfo(for: screen)
        var cameraWidth = raw.cameraWidth
        var safeAreaTop = raw.safeAreaTop
        // Owner spec, 2026-10-25: "Notch" vs "Island" in Island Settings — only meaningful on a
        // display that actually has a real notch. The single source of truth every notch-aware
        // branch downstream already keys off is `IslandGeometry.isNotched`, itself derived purely
        // from `safeAreaTop`/`cameraWidth` — zeroing both here, before they ever reach
        // `IslandGeometry.init`, is what makes every one of those branches (collapsed sizing/
        // positioning, the fused bar's own rendering, drag-locking, the native silhouette's fill)
        // fall back to the exact same behavior a non-notched display already has in "Island" mode,
        // with no separate setting check needed at any of those call sites.
        if let uuid = screen.stableDisplayUUIDString, IslandSettings.notchAttachmentMode(forDisplayUUID: uuid) == .island {
            cameraWidth = 0
            safeAreaTop = 0
        }
        let menuBarHeight = measurements.height(
            displayID: screen.notchDisplayID, frame: screen.frame, visibleTop: screen.visibleFrame.maxY,
            scale: screen.backingScaleFactor, statusBarThickness: NSStatusBar.system.thickness
        )
        return IslandGeometry(
            screen: screen.frame, safeAreaTop: safeAreaTop, cameraWidth: cameraWidth,
            menuBarHeight: menuBarHeight, topMargin: IslandSettings.edgeMargin(for: .top)
        )
    }

    /// Owner-reported, 2026-10-24: a real camera notch used to hang the *collapsed* pill flush
    /// from the top edge, sized to its own housing (IslandGeometry.collapsedSize) — invisible,
    /// since nothing can draw over the real camera cutout. The collapsed icon on a notched top
    /// dock is now a plain circle beside the notch instead (windowFrame(for:)'s own `.top` case
    /// positions it), sized to the notch's own height so it still reads as sitting right in the
    /// menu bar row rather than floating at some unrelated size. Every other case — every edge
    /// without a real notch — is still always CollapsedPill's own plain circle at its configured
    /// diameter (IslandSettings.pillDiameter). The *expanded* card's own sizing
    /// (expandedSize(for:geometry:)) is unaffected — it still grows centered, flush over the real
    /// notch, unchanged.
    /// Owner spec, 2026-10-24 (superseding the single-circle-beside-the-notch version this
    /// replaced): on a real notch, the collapsed window spans the notch's own width plus one
    /// `notchWingWidth`-wide wing on each side — see NotchExtensionBar's own doc comment for what
    /// actually renders inside that span. Height is always the notch's own height
    /// (`geometry.cameraHeight`), never taller, per the owner's explicit constraint — owner
    /// request, 2026-10-25: "reduce the height by a very little bit" then, once applied, "increase
    /// the height a very tiny bit" (it had gone slightly too far the other way) — settled at 2pt
    /// off, not the original 4. Same pass also shrank `notchWingWidth` ("reduce the width a bit
    /// more") from the first-cut 44 down to 32.
    private static let notchWingWidth: CGFloat = 32
    private static let notchBarHeightReduction: CGFloat = 3

    private static func collapsedSize(for edge: DockEdge, geometry: IslandGeometry) -> CGSize {
        if edge == .top && geometry.isNotched {
            let height = max(16, geometry.cameraHeight - notchBarHeightReduction)
            return CGSize(width: geometry.cameraWidth + notchWingWidth * 2, height: height)
        }
        return DockPlacement.collapsedPillSize(for: edge, diameter: IslandSettings.pillDiameter)
    }

    /// The native silhouette's own shape inset for the *collapsed* pill — non-nil (a full circle,
    /// not NotchSilhouetteView's "card" radius) on every edge except a real top-edge camera
    /// notch, which hangs flush instead (IslandGeometry.floatingGap is already nil there,
    /// matching `isNotched`'s own doc comment: both collapsed and expanded are flush/attached to
    /// a real notch now). Left/right/bottom never had an equivalent of IslandGeometry's own notch
    /// detection, so they always get the same small flat inset regardless of what the display
    /// reports.
    private static func collapsedGap(edge: DockEdge, geometry: IslandGeometry) -> CGFloat? {
        edge == .top ? geometry.floatingGap : DockPlacement.collapsedPillInset
    }

    /// ExpandedCard's own fixed size, capped against the real screen's bounds for safety on a
    /// small/unusual display.
    private static func expandedSize(for edge: DockEdge, geometry: IslandGeometry) -> CGSize {
        let base = edge.isVertical ? expandedCardSizeVertical : expandedCardSize
        let width = min(base.width, geometry.screen.width - 24)
        let height = min(base.height, geometry.screen.height - 48)
        return CGSize(width: width, height: max(80, height))
    }

    /// `.top` keeps IslandGeometry.frame(for:)'s own anchor math (notch fusion / menu-bar drop),
    /// shifted by the current drag offset, which that method knows nothing about on its own; the
    /// other three edges go through DockPlacement entirely.
    ///
    /// `symmetric` (the collapsed pill's own settled state — see `layoutContent`'s own doc
    /// comment): `size` is now bigger on the docked side too (shadowMargin, not flush), so without
    /// compensating here, the pill's own *visual* distance from the screen edge would become
    /// `IslandSettings.edgeMargin(for:) + shadowMargin` instead of just what that setting actually
    /// says. Shifts the window itself to cancel that out exactly, so the setting stays accurate —
    /// the extra room is still there for hover-scale/shadow to bleed into, it's just invisible
    /// window backing-store space the content is centered away from, not a visible gap.
    private func windowFrame(for size: CGSize, symmetric: Bool = false, isExpanded: Bool = false) -> CGRect {
        if let corner = dockedCorner {
            // The actual fix for "the tray opens from a displaced position": `cornerFrame` is
            // fully determined by `corner` alone (see its own doc comment) — the same physical
            // screen point stays flush between the small collapsed quarter-disc and the much
            // larger expanded card, so there's nothing here for a size change to ever need to
            // shift, unlike a single-edge dock's offset (which only has one free axis to begin
            // with, not the "which direction does the card grow" problem a corner has on both).
            // Same symmetric/margin compensation reasoning as the single-edge branch below, just
            // applied to both axes instead of one, since both are flush at a corner.
            let margin = symmetric
                ? IslandSettings.edgeMargin(for: .top) - Self.shadowMargin : IslandSettings.edgeMargin(for: .top)
            return DockPlacement.cornerFrame(for: size, corner: corner, visibleFrame: visibleFrame, margin: margin)
        }
        if isFreePositioned {
            // The collapsed pill still just centers on `freeCenter` — unchanged, same reasoning as
            // ever (below). The *expanded* card no longer does: owner spec (2026-10-21) — a
            // free-floating tray opens adjacent to the island, in whichever direction
            // `DockPlacement.trayDirection(for:)` names for the island's own grid region, rather
            // than growing symmetrically outward around the same center the pill rests at (which
            // routinely covered the island itself). `isExpanded` is what distinguishes the two —
            // `symmetric` can't: it's unconditionally true for *every* free-positioned call,
            // collapsed or expanded alike (every call site already notes this), so it carries no
            // information about which one this actually is.
            if isExpanded {
                return freeFloatingTrayFrame(for: size)
            }
            // Free placement has no docked edge to be flush against, so `size` (the envelope,
            // already inclusive of shadowMargin) is always centered directly on `freeCenter` —
            // the collapsed pill grows outward around the same point it rests at, regardless of
            // `symmetric`. `freeCenter` itself only ever gets clamped against the small
            // *collapsed* pill's own footprint (settleFreePositioned's own doc comment) —
            // clamping it against the much larger expanded card's footprint instead, up front,
            // used to push any pill placed within ~150-190pt of an edge inward to that same fixed
            // distance every time, no matter where it was actually dropped. Clamping fresh here,
            // against whichever `size` is actually being resolved right now, means the resting
            // pill stays exactly where it was dropped (its own envelope is small enough to need
            // little or no correction almost everywhere).
            let halfWidth = size.width / 2
            let halfHeight = size.height / 2
            let clampedCenterX = min(max(freeCenter.x, visibleFrame.minX + halfWidth), visibleFrame.maxX - halfWidth)
            let clampedCenterY = min(max(freeCenter.y, visibleFrame.minY + halfHeight), visibleFrame.maxY - halfHeight)
            return CGRect(x: clampedCenterX - halfWidth, y: clampedCenterY - halfHeight, width: size.width, height: size.height)
        }
        switch edge {
        case .top:
            // Owner spec, 2026-10-24: a real camera notch used to center the collapsed pill flush
            // over the notch itself — invisible, since nothing can draw over the physical camera
            // cutout. The collapsed state is now a fused two-wing bar centered on the notch
            // instead (NotchExtensionBar's own doc comment; collapsedSize(for:geometry:) already
            // sizes it notch-width-plus-a-wing-on-each-side), so it wants the exact same centered,
            // flush-top placement `geometry.frame(for:)` below already gives the expanded card —
            // no separate branch needed anymore now that both states share one centered shape.
            // `offset` re-clamped fresh here, against whichever `size` is actually being resolved
            // right now — same reasoning as the `.bottom, .left, .right` branch just below (its own
            // doc comment has the full story). `.top` used to add the raw, pill-sized `offset`
            // straight into `geometry.frame(for:)`'s result with no bound at all, so a pill (or,
            // worse, the much wider expanded card) docked near a left/right corner could legitimately
            // overflow the real screen edge — not just the invisible shadow-margin envelope, but far
            // enough to get hard-clipped by the OS, which is what read as "part of it is hidden."
            var frame = geometry.frame(for: size)
            // Owner-reported, 2026-10-25: "the notch comes into the screen on collapse" — on
            // collapse, the settled pill's frame (symmetric: true) landed 40pt (exactly
            // `shadowMargin`) above the real screen top, confirmed live via DIAG logging twice:
            // `screenTop=1112` but `computed`/`actual` frame had `origin.y + height == 1152`.
            // Root cause: `IslandGeometry.frame(for:)`'s own `origin.y` formula
            // (`screen.maxY - floatingDrop - size.height`) already pins the top edge flush to the
            // real screen top *for any `size`* — size-independent by construction — so
            // `restingEnvelopeSize(for:edge:symmetric: true)` already padding `size`'s height by
            // `shadowMargin * 2` (margin on both top and bottom) has nowhere to put the "top" half
            // of that margin except below the flush top edge anyway. Shifting the frame up by one
            // more `shadowMargin` here double-applies that same margin for the non-notched path —
            // confirmed, with real numbers, not present for the notched early-return path below
            // (an earlier attempt to delete this line outright for *every* path broke that one:
            // "it is now not in the notch again" — `guard !geometry.isNotched else { return frame
            // }` returns *before* `adaptiveOffset` ever runs, making this the ONLY position
            // adjustment a notched display's collapsed bar gets, for reasons specific to that path
            // that don't carry over here). So: still applied for the notched return below,
            // deliberately skipped for the non-notched path that showed the real, confirmed bug.
            if geometry.isNotched {
                if symmetric { frame.origin.y += Self.shadowMargin }
                return frame
            }
            // Owner-reported, 2026-10-25: a real notch's fused bar is meant to stay permanently
            // centered on the notch, not draggable along the edge — any `offset` persisted from
            // when the top dock was still a plain draggable pill (before this feature existed)
            // would otherwise still get applied here, visibly shifting the bar off-center from
            // the real notch for no reason the user did on *this* build.
            let adaptiveOffset: CGFloat
            if let range = DockPlacement.offsetRange(forSize: size, edge: edge, visibleFrame: visibleFrame, margin: 8) {
                adaptiveOffset = min(max(offset, range.lowerBound), range.upperBound)
            } else {
                adaptiveOffset = 0
            }
            frame.origin.x += adaptiveOffset
            return frame
        case .bottom, .left, .right:
            let margin = symmetric ? IslandSettings.edgeMargin(for: edge) - Self.shadowMargin : IslandSettings.edgeMargin(for: edge)
            // `offset` (the *persisted* value, clamped only against the small collapsed pill's
            // own range — see `dockToEdge`'s own doc comment) is re-clamped fresh here, against
            // whichever `size` is actually being resolved right now, same reasoning and same bug
            // this fixed for free placement just above: using the raw, pill-sized `offset`
            // directly for the much taller/wider expanded card's own frame could request a frame
            // that doesn't fit — nothing would correct that, so macOS's own window-placement
            // safeguards would force it elsewhere the instant it expanded (a visible jump to a
            // different position than where the pill was actually resting).
            let adaptiveOffset: CGFloat
            if let range = DockPlacement.offsetRange(forSize: size, edge: edge, visibleFrame: visibleFrame, margin: 8) {
                adaptiveOffset = min(max(offset, range.lowerBound), range.upperBound)
            } else {
                adaptiveOffset = 0
            }
            return DockPlacement.frame(for: size, edge: edge, offset: adaptiveOffset, visibleFrame: visibleFrame, margin: margin)
        }
    }

    /// `windowFrame(for:isExpanded:)`'s own free-floating, expanded-only branch — owner spec
    /// (2026-10-21): the tray opens adjacent to the island (never over it), in the direction its
    /// own 3x3 grid region names, flipping to the opposite side first if the preferred one
    /// doesn't fit, and only clamping as a last resort. `DockPlacement.trayPlacement(...)` is pure
    /// and works in *content* terms (the actual visible pill/card, not the padded envelope); `size`
    /// here is always the symmetric envelope (content inflated by `shadowMargin` on all four
    /// sides — true for every free-positioned call, `windowFrame`'s own doc comment on why
    /// `symmetric` itself can't be trusted to say so), so the content size this function actually
    /// needs is recovered by stripping that same padding back off before calling into it, and the
    /// placement it returns gets the same padding added back to turn it into this envelope's frame.
    private func freeFloatingTrayFrame(for envelopeSize: CGSize) -> CGRect {
        let contentSize = CGSize(width: envelopeSize.width - Self.shadowMargin * 2, height: envelopeSize.height - Self.shadowMargin * 2)
        let placement = freeFloatingPlacement(forContentSize: contentSize)
        let envelopeOrigin = CGPoint(x: placement.origin.x - Self.shadowMargin, y: placement.origin.y - Self.shadowMargin)
        return CGRect(origin: envelopeOrigin, size: envelopeSize)
    }

    /// Shared by `freeFloatingTrayFrame(for:)` (the window's own placement) and `freeFloatingNotch()`
    /// (the card's own notch position) — both need the *same* placement decision, not two
    /// independently-computed ones that could disagree about which direction the tray actually
    /// went.
    private func freeFloatingPlacement(forContentSize contentSize: CGSize) -> (origin: CGPoint, direction: TrayDirection) {
        let islandSize = Self.collapsedSize(for: effectiveEdgeForGeometry, geometry: geometry)
        let region = DockPlacement.gridRegion(for: freeCenter, visibleFrame: visibleFrame)
        let preferredDirection = DockPlacement.trayDirection(for: region)
        return DockPlacement.trayPlacement(
            islandCenter: freeCenter, islandSize: islandSize, traySize: contentSize, preferredDirection: preferredDirection,
            gap: Self.freeTrayGap, visibleFrame: visibleFrame
        )
    }

    /// Free-floating only: which edge of the card the notch sits on, and how far along it, so it
    /// stays aligned with the island (`DockPlacement.notchOffset(...)`'s own doc comment) —
    /// `nil` for every other placement mode (edge dock, corner dock), which keep
    /// `CutoutTabShape`'s own default centered tab untouched. Uses the *expanded* card's real
    /// content size, not whatever `currentSize` happens to be at the moment this is called — it
    /// only ever matters while the card is actually showing.
    func freeFloatingNotch() -> (dock: CardDock, offset: CGFloat, anchor: UnitPoint)? {
        guard isFreePositioned, dockedCorner == nil else { return nil }
        let cardContentSize = Self.expandedSize(for: effectiveEdgeForGeometry, geometry: geometry)
        let placement = freeFloatingPlacement(forContentSize: cardContentSize)
        let notchDock: CardDock
        switch DockPlacement.notchDirection(for: placement.direction) {
        case .up: notchDock = .top
        case .down: notchDock = .bottom
        case .left: notchDock = .left
        case .right: notchDock = .right
        }
        let offset = DockPlacement.notchOffset(
            islandCenter: freeCenter, trayOrigin: placement.origin, traySize: cardContentSize, direction: placement.direction,
            cornerRadius: 33, notchHalfLength: Self.cardCutoutTabHalfLength(forVertical: notchDock.isVertical)
        )
        // Owner spec, step 3: "the open animation originates from the island's position." Same
        // along-edge position the notch itself sits at (just expressed as a 0...1 UnitPoint
        // instead of a raw offset) — reusing it rather than recomputing from `freeCenter` directly
        // is what guarantees the animation's own anchor and the notch's own position can never
        // disagree about where the island actually is.
        let anchor: UnitPoint
        switch notchDock {
        case .top: anchor = UnitPoint(x: 0.5 + offset / cardContentSize.width, y: 0)
        case .bottom: anchor = UnitPoint(x: 0.5 + offset / cardContentSize.width, y: 1)
        case .left: anchor = UnitPoint(x: 0, y: 0.5 + offset / cardContentSize.height)
        case .right: anchor = UnitPoint(x: 1, y: 0.5 + offset / cardContentSize.height)
        }
        return (notchDock, offset, anchor)
    }

    /// `ExpandedCard.tabLengthAlongEdge`'s own two values, mirrored here (that file's own
    /// doc comment) — `freeFloatingNotch()` needs the same "how long is the notch" figure to
    /// clamp its offset away from the card's rounded corners, and ExpandedCard is a SwiftUI view,
    /// not something NotchPanel can just ask directly.
    private static func cardCutoutTabHalfLength(forVertical isVertical: Bool) -> CGFloat {
        (isVertical ? 92 : 116) / 2
    }

    /// Real, visible space between the island and the tray when free-floating — enough that they
    /// read as two distinct things, not touching (`DockPlacement.trayOrigin(...)`'s own `gap`).
    /// Owner request: pulled in tighter than the original 10pt so the tray reads as closer to —
    /// almost touching — the island it unfolded from.
    private static let freeTrayGap: CGFloat = 4

    // MARK: - Present (envelope-then-settle resize)

    /// `suppressPhotoFlight` sets `NotchUIState.isRepositioningEdge` for the duration of this one
    /// swing (cleared again once it settles) — see that property's own doc comment for why an
    /// edge-switch's internal collapse/expand asks for this and an ordinary one doesn't. Every
    /// call sets it fresh, one way or the other, rather than only ever setting it true: that way
    /// a plain (non-suppressing) present() arriving mid-swing — an unrelated collapse/expand that
    /// supersedes this one — always leaves the flag correct for itself, the same reasoning
    /// `presentImmediately` already applies to `isAnimating` below.
    private func present(expanded: Bool, suppressPhotoFlight: Bool = false, completion: @escaping () -> Void = {}) {
        let target = expanded ? Self.expandedSize(for: effectiveEdgeForGeometry, geometry: geometry) : Self.collapsedSize(for: effectiveEdgeForGeometry, geometry: geometry)
        guard target != currentSize else {
            uiState.isExpanded = expanded
            uiState.isAnimating = false
            // No actual swing happens in this branch, so there's nothing to suppress — and
            // nowhere below to ever clear it again if it were set true here.
            uiState.isRepositioningEdge = false
            completion()
            return
        }

        presentGeneration += 1
        let generation = presentGeneration

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start = currentSize
        // Updated immediately (not just on completion) so a second present() call arriving before
        // this one finishes compares against where we're actually headed, not the stale
        // pre-animation size — that staleness is what let a superseded transition's completion
        // leave the window sized for the wrong state.
        currentSize = target

        // Set before the swing starts, not after — still true even though the backdrop itself is
        // about to be hidden below: it reappears mid-fade if a generation gets superseded, and it
        // has to already show the right theme/color at that point, not the stale default.
        silhouette.setFillColor(currentSilhouetteFillColor())

        // NotchView's own `.transition` now performs the actual visible pill<->card crossfade
        // (scale, opacity, blur) — see its own doc comment — so the SwiftUI content's AppKit-level
        // hosting frame has to already be big enough to hold *both* states for the whole swing,
        // not just `target`, which for a collapse is the small pill. Sizing hosting to that small
        // target immediately would correctly position the newly-inserted (still fading-in) pill,
        // but would leave the still-large, still-fading-out card positioned for a frame it no
        // longer has. The same "grow first / shrink last" rule the window itself follows applies
        // here too: use whichever of (start, target) is the *expanded* one for the whole visible
        // swing, and only settle down to the true small target in the completion handler below.
        let contentLayoutSize = MotionConstants.windowResizeOrdering(forExpanding: expanded) == .growBeforeAnimating ? target : start

        // design/DESIGN_GUIDE.md §9.1 point 1 / §9.2 point 4 (MotionConstants.windowResizeOrdering):
        // "window first" on the way in, "window last" on the way out. The window always grows to
        // an envelope that already fits `contentLayoutSize` (the larger of start/target, plus the
        // same shadow margin the resting state uses) *immediately*, before any visible motion
        // starts — not IslandMotion's old spring-overshoot reservation, sized only for `target`.
        // That used to compute a *smaller* envelope than `contentLayoutSize` actually needs
        // whenever a collapse's `contentLayoutSize` (the still-large outgoing card) was bigger
        // than its own `target` (the small pill) — shrinking the window out from under the
        // still-large, still-visible card the instant the swing began, instead of only once it
        // settles. An expand's `contentLayoutSize` already equals `target`, so this envelope and
        // the completion handler's own `restingEnvelopeSize` come out identical there and the
        // window never needs to move at all mid-swing; a collapse's don't, which is exactly the
        // shrink this envelope now correctly defers to the completion handler below.
        // Free placement has no docked edge to be flush against mid-swing either — always
        // symmetric, same reasoning as the settled states above.
        let envelope = self.envelopeSize(for: contentLayoutSize, symmetric: isFreePositioned)
        // `contentLayoutSize` is always the *expanded* size for the whole swing, either direction
        // ("grow first/shrink last" — this function's own doc comment above), so the window is
        // always card-sized here regardless of whether this is an expand or a collapse — the
        // free-floating tray placement branch (`windowFrame(for:isExpanded:)`'s own doc comment)
        // applies for the entire swing, not just half of it.
        setFrame(windowFrame(for: envelope, symmetric: isFreePositioned, isExpanded: true), display: true)
        layoutContent(for: contentLayoutSize, envelopeSize: envelope, symmetric: isFreePositioned)
        // Forces AppKit to resolve that frame change — and SwiftUI's own layout pass inside
        // `hosting` to catch up with it — synchronously, right now, rather than on whatever the
        // next display-link callback happens to be. Without this, the brand-new view NotchView's
        // transition is about to insert (ExpandedCard on an expand, CollapsedPill on a collapse)
        // could render its first frame or two against the *previous* (smaller, pre-swing) hosting
        // geometry: GeometryReader-based layout (ExpandedCard's own hero section positions its
        // children off `geo.size`) degenerates toward the corner when the space it measures is
        // still the old, much smaller one, which is exactly what read as content "arriving from
        // the top-left" before snapping to its real position a frame later.
        hosting.layoutSubtreeIfNeeded()

        // The pill's full-circle shape only ever belongs to the small collapsed indicator — the
        // wide expanded card is always a plain rounded rectangle (gap nil).
        let targetGap = expanded ? nil : Self.collapsedGap(edge: effectiveEdgeForGeometry, geometry: geometry)

        // The native backdrop only ever matters for the *static*, at-rest silhouette (the shape
        // both CollapsedPill and ExpandedCard already draw their own complete background and
        // border on top of — see CollapsedPill's own doc comment on why that split exists) and for
        // hit-testing when nothing's animating. NotchView's own SwiftUI transition now draws and
        // animates that whole background/content/border itself, visibly, for the entire swing —
        // so growing the backdrop independently alongside it no longer has anything useful left to
        // contribute, and only ever read as a second, differently-curved shape arriving on its own
        // (an empty, bordered box, then content catching up inside it moments later). Hide it
        // outright for the swing's duration instead, and let SwiftUI carry all of the visible
        // motion; it reappears below, already correctly sized/colored for the new resting state,
        // once the swing settles.
        silhouette.alphaValue = 0

        // Set synchronously, not inside the withAnimation block below: NotchView's pill-visibility
        // logic (`isPillVisible`) reads this directly, via a `.transaction { $0.animation = nil }`
        // that already strips any animation from that read regardless — it only has to be true
        // before the swing's first frame renders, not animated itself. Same reasoning for
        // `isRepositioningEdge` just below it: NotchView's photoNamespace gating has to already
        // be correct before ExpandedCard/CollapsedPill's first frame of this swing, not catch up
        // to it mid-animation.
        uiState.isAnimating = true
        uiState.isRepositioningEdge = suppressPhotoFlight
        let cardTransitionKind = expanded
            ? MotionConstants.expandTransitionKind(reduceMotion: reduceMotion)
            : MotionConstants.collapseTransitionKind(reduceMotion: reduceMotion)
        // Owner-reported, 2026-10-25: "the notch comes into the screen on collapse" — the card
        // floating loose mid-swing before snapping into place. Confirmed via diagnostic logging:
        // the bug only ever reproduced under the spring curve, never Reduce Motion's plain
        // crossfade, and survived forcing `cardTransition` itself to plain opacity — ruling out
        // `.scale(anchor:)` and pointing at the animation curve/completion timing instead.
        // `.logicallyComplete` fires before a spring/`combined(with:)` transition has actually
        // finished settling/removing itself on screen in general (not just an overshooting one —
        // the collapse spring itself is critically damped, no overshoot, and still showed this);
        // the completion handler below snaps the real AppKit window frame to its final small size,
        // so it needs the later, more conservative `.removed` to avoid firing while the transition
        // is still visually catching up.
        //
        // A later attempt to decouple `isAnimating` (gates `isPillVisible`) onto an earlier timer,
        // so the pill wouldn't wait through `.removed`'s longer margin with nothing on screen
        // (owner-reported, same day: "on collapse the notch hides for a second, and the tray has
        // disappeared"), made things *worse*, not better (owner-reported, same day: "it is now
        // displacing again") — it let the pill become visible, ZStack-aligned within the window,
        // *before* the frame-snap below had actually shrunk that window down to its true small
        // target, so the pill rendered flush-top within a window that was still card-sized. Both
        // symptoms need the SAME completion to fire at the SAME moment; the "pill disappears for a
        // moment" gap is accepted as-is for now rather than risk reintroducing the floating bug
        // again — don't decouple these two without a fundamentally different mechanism.
        withAnimation(cardTransitionKind.animation, completionCriteria: .removed) {
            uiState.isExpanded = expanded
        } completion: { [weak self] in
            guard let self, generation == self.presentGeneration else { return }
            self.uiState.isAnimating = false
            self.uiState.isRepositioningEdge = false
            // Settle the window back down to the target size, plus the resting shadow margin
            // (restingEnvelopeSize) — not exactly the target, or CollapsedPill/ExpandedCard's own
            // shadows would have nowhere to bleed into and clip right back at the window edge.
            // This is also where the hosting content frame (kept at the larger
            // `contentLayoutSize` above for the whole visible swing) finally shrinks down to the
            // true small target on a collapse — the "shrink after animating" half of the same rule.
            // symmetric: !expanded — only the pill's own settled state gets margin on its docked
            // side too (layoutContent's own doc comment); the settled card stays flush, unchanged.
            // Free placement has no docked edge at all, so it's always symmetric regardless of
            // `expanded` — both the pill and the card center on `freeCenter`.
            let symmetricNow = self.isFreePositioned || !expanded
            let restEnvelope = self.envelopeSize(for: target, symmetric: symmetricNow)
            let restFrame = self.windowFrame(for: restEnvelope, symmetric: symmetricNow, isExpanded: expanded)
            self.setFrame(restFrame, display: true)
            self.layoutContent(for: target, envelopeSize: restEnvelope, symmetric: symmetricNow)
            // The backdrop reappears here already showing whichever final state (fill color set
            // above, shape) this swing actually ended at.
            self.silhouette.resize(
                to: target, from: target, startGap: targetGap, targetGap: targetGap,
                envelopeSize: restEnvelope, symmetric: symmetricNow, reduceMotion: true, completion: {}
            )
            self.silhouette.alphaValue = 1
            completion()
        }
    }

    /// Snaps straight to the resting frame for the current `expanded` state with no animation at
    /// all — used for a screen change (`reposition()`) and for the "move the pill" step of an
    /// edge change (design/DESIGN_GUIDE.md §6: "Never animate the card across the screen").
    private func presentImmediately(expanded: Bool) {
        uiState.isExpanded = expanded
        let target = expanded ? Self.expandedSize(for: effectiveEdgeForGeometry, geometry: geometry) : Self.collapsedSize(for: effectiveEdgeForGeometry, geometry: geometry)
        currentSize = target
        presentGeneration += 1 // supersede any in-flight animated present()
        // That supersession means an in-flight present()'s own completion handler (the only other
        // place this clears) will never fire — without resetting it here too, interrupting an
        // animated swing with an edge change or a screen change could leave this stuck true
        // forever, hiding the pill even once correctly settled back at rest.
        uiState.isAnimating = false
        // Same reasoning as `isAnimating` just above: nothing is swinging here, so nothing needs
        // to stay suppressed.
        uiState.isRepositioningEdge = false
        silhouette.setFillColor(currentSilhouetteFillColor())
        // symmetric: !expanded — see layoutContent's own doc comment. Free placement is always
        // symmetric, same reasoning as the animated present() completion above.
        let symmetricNow = isFreePositioned || !expanded
        let restEnvelope = envelopeSize(for: target, symmetric: symmetricNow)
        let restFrame = windowFrame(for: restEnvelope, symmetric: symmetricNow, isExpanded: expanded)
        setFrame(restFrame, display: true)
        layoutContent(for: target, envelopeSize: restEnvelope, symmetric: symmetricNow)
        let gap = expanded ? nil : Self.collapsedGap(edge: effectiveEdgeForGeometry, geometry: geometry)
        silhouette.resize(
            to: target, from: target, startGap: gap, targetGap: gap,
            envelopeSize: restEnvelope, symmetric: symmetricNow, reduceMotion: true, completion: {}
        )
    }

    /// Centers the silhouette and the SwiftUI content within the (always at-least-as-large-as-
    /// target, thanks to restingEnvelopeSize's shadow margin even at rest) envelope window.
    ///
    /// `symmetric`: the collapsed pill's own settled state only, never the expanded card and
    /// never mid-swing (the mid-swing window stays card-sized the whole time regardless of
    /// direction — "grow first/shrink last" — so there's nothing pill-shaped to symmetrize until
    /// the swing actually finishes). Flush-against-the-edge, by design, left the pill with zero
    /// envelope room on the near/docked side for its own hover-scale growth
    /// (MotionConstants.pillHoverScale) and shadow/glow to bleed into — clipped flat against the
    /// window's own hard edge on hover, a "chip" on whichever side faces the docked edge. Passed
    /// through to `silhouette.resize(...)`'s own `symmetric` too, so the native backdrop centers
    /// the same way and stays aligned with this SwiftUI content.
    ///
    /// `silhouette.resize(...)` also sets its own frame to `envelopeSize` while it's actively
    /// animating, but nothing resets it once the animation finishes and the window shrinks back
    /// down — without doing it here too, the silhouette view stayed sized to the stale, larger
    /// envelope while its parent container shrunk around it, so the shape's internal path
    /// positioning (computed relative to that envelope) ended up off-center in the real window,
    /// clipping its outline unevenly on one side.
    private func layoutContent(for size: CGSize, envelopeSize: CGSize, symmetric: Bool = false) {
        guard let container = contentView else { return }
        container.frame = NSRect(origin: .zero, size: envelopeSize)
        silhouette.frame = NSRect(origin: .zero, size: envelopeSize)
        hosting.frame = CGRect(origin: contentOrigin(for: size, envelopeSize: envelopeSize, symmetric: symmetric), size: size)
    }

    /// Where `size` sits within `envelopeSize`. `symmetric`: centered on both axes (see
    /// `layoutContent`'s own doc comment). Otherwise: flush against the docked edge's own side
    /// (nothing needs to render past a flush edge), centered on the perpendicular axis. Mirrors
    /// `restingEnvelopeSize(for:edge:symmetric:)`'s own margin placement.
    private func contentOrigin(for size: CGSize, envelopeSize: CGSize, symmetric: Bool = false) -> CGPoint {
        guard !symmetric else {
            return CGPoint(x: (envelopeSize.width - size.width) / 2, y: (envelopeSize.height - size.height) / 2)
        }
        switch edge {
        case .top:
            return CGPoint(x: (envelopeSize.width - size.width) / 2, y: envelopeSize.height - size.height)
        case .bottom:
            return CGPoint(x: (envelopeSize.width - size.width) / 2, y: 0)
        case .left:
            return CGPoint(x: 0, y: (envelopeSize.height - size.height) / 2)
        case .right:
            return CGPoint(x: envelopeSize.width - size.width, y: (envelopeSize.height - size.height) / 2)
        }
    }
}
