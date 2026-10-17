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
    /// Above the menu bar's own status items, below native menus.
    static let normalLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "NotchPanel")

    private let headphoneState: HeadphoneState
    private let uiState = NotchUIState()
    private let onSelectNoiseMode: (CommandableNoiseMode) -> Void
    private let isModeVerified: (CommandableNoiseMode) -> Bool
    private let supportsNoiseControl: () -> Bool
    private let onReconnectTapped: () -> Void
    private let onOpenBluetoothSettingsTapped: () -> Void
    private let lastMatchedProfileDisplayName: () -> String?

    private let silhouette = NotchSilhouetteView(frame: .zero)
    private var hosting: NSHostingView<NotchView>!

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

    private var currentSize: CGSize
    /// Bumped on every present() call; a stale completion whose generation no longer matches is
    /// dropped instead of applying its (now outdated) frame/content, which is what let a
    /// superseded transition leave the window sized for one state while content rendered for
    /// another — an oversized, seemingly empty shape.
    private var presentGeneration = 0

    private var menuBarMeasurements = MenuBarMeasurements()
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
    /// clipped by the window's edge. The docked edge itself stays flush (nothing needs to render
    /// past a flush edge); the margin only goes on the other three sides — see
    /// `restingEnvelopeSize(for:edge:)`.
    private static let shadowMargin: CGFloat = 40

    /// Inflates `contentSize` for the resting envelope: double margin on the two sides
    /// perpendicular to `edge` (symmetric, since the content is centered along the edge), single
    /// margin on the far side along the docked axis (the near side is flush against the docked
    /// edge, so it needs none).
    private static func restingEnvelopeSize(for contentSize: CGSize, edge: DockEdge) -> CGSize {
        edge.isVertical
            ? CGSize(width: contentSize.width + shadowMargin, height: contentSize.height + shadowMargin * 2)
            : CGSize(width: contentSize.width + shadowMargin * 2, height: contentSize.height + shadowMargin)
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
        lastMatchedProfileDisplayName: @escaping () -> String?
    ) {
        self.headphoneState = headphoneState
        self.onSelectNoiseMode = onSelectNoiseMode
        self.isModeVerified = isModeVerified
        self.supportsNoiseControl = supportsNoiseControl
        self.onReconnectTapped = onReconnectTapped
        self.onOpenBluetoothSettingsTapped = onOpenBluetoothSettingsTapped
        self.lastMatchedProfileDisplayName = lastMatchedProfileDisplayName

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
        self.currentSize = Self.collapsedSize(for: resolvedEdge, geometry: initialGeometry)

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
                    self.map { Self.collapsedSize(for: $0.edge, geometry: $0.geometry) } ?? .zero
                },
                onSelectNoiseMode: onSelectNoiseMode, isModeVerified: isModeVerified,
                supportsNoiseControl: supportsNoiseControl, isNotched: { [weak self] in self?.isNotched ?? false },
                dockEdge: { [weak self] in self?.edge ?? .top },
                onCollapseTabTapped: { [weak self] in self?.handleTabTap() },
                onReconnectTapped: onReconnectTapped, onOpenBluetoothSettingsTapped: onOpenBluetoothSettingsTapped,
                lastMatchedProfileDisplayName: lastMatchedProfileDisplayName
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

        let initialEnvelope = Self.restingEnvelopeSize(for: currentSize, edge: edge)
        let container = NSView(frame: NSRect(origin: .zero, size: initialEnvelope))
        container.wantsLayer = true
        container.layer?.masksToBounds = false
        container.addSubview(silhouette)
        container.addSubview(hosting)
        contentView = container

        silhouette.onTap = { [weak self] in self?.handleTap() }
        silhouette.onDrag = { [weak self] delta in self?.handleDrag(delta) }
        silhouette.dockEdge = edge

        layoutContent(for: currentSize, envelopeSize: initialEnvelope)
        setFrame(windowFrame(for: initialEnvelope), display: false)
        logger.info("NotchPanel created. frame=\(NSStringFromRect(self.frame), privacy: .public) edge=\(self.edge.rawValue, privacy: .public)")
        silhouette.setFillColor(currentSilhouetteFillColor())
        // Give the silhouette an initial path immediately — otherwise it stays empty (zero
        // frame) until the first expand/collapse transition ever runs.
        let initialGap = Self.collapsedGap(edge: edge, geometry: initialGeometry)
        silhouette.resize(
            to: currentSize, from: currentSize,
            startGap: initialGap, targetGap: initialGap,
            envelopeSize: initialEnvelope, reduceMotion: true, completion: {}
        )

        syncScreenEdgeMonitors()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
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

    func handleClassicDisconnected() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        collapse()
    }

    // MARK: - Settings changed (size/silhouette/fits/outline/display/edge)

    var isNotched: Bool { edge == .top && geometry.isNotched }
    var currentEdge: DockEdge { edge }

    /// The fallback NSStatusItem menu's own "Island Settings…" item — see
    /// NotchUIState.islandSettingsRequestToken's own doc comment for why it has to go through
    /// NotchView instead of opening the window directly from here.
    func requestOpenIslandSettings() {
        uiState.islandSettingsRequestToken += 1
    }

    func settingsDidChange() {
        // Forced, not a plain reposition(): a margin change on bottom/left/right isn't visible to
        // reposition()'s own "did anything actually change" guard at all — IslandSettings.edgeMargin
        // is read live inside windowFrame(for:), not stored on `geometry`/`currentSize`, the only
        // two things that guard compares. Without forcing it, that guard saw no difference and
        // bailed out before ever calling presentImmediately(), so the window silently never moved.
        reposition(force: true)
    }

    /// Island Settings' edge picker calls this directly (not through `settingsDidChange()`,
    /// which just repositions on the *current* edge) — design/DESIGN_GUIDE.md §6: "Changing the
    /// edge while the card is expanded: collapse first, move the pill, then expand from the new
    /// edge. Never animate the card across the screen."
    func setDockEdge(_ newEdge: DockEdge) {
        guard newEdge != edge else { return }
        switch DockPlacement.edgeChangeOrdering(isExpanded: uiState.isExpanded) {
        case .collapseFirst:
            // NotchUIState.isRepositioningEdge's own doc comment: this collapse/expand pair is
            // triggered internally to relocate the card, not by the user tapping to actually
            // close it, so the hero photo shouldn't fly to the pill for it — only the card
            // shape's own scale+fade motion should play. `suppressPhotoFlight: true` on both
            // calls below (not just the first) — `presentImmediately`'s own "move the pill" step
            // in between unconditionally resets the flag, so the expand has to ask again, fresh.
            //
            // Collapse (normally animated — this step doesn't relocate anything, so there's
            // nothing wrong with animating it) on the *old* edge, wait for that to actually
            // finish, only then move the pill (unanimated — this is the step that would
            // otherwise visibly cross the screen) and expand from the new edge.
            collapse(suppressPhotoFlight: true) { [weak self] in
                guard let self else { return }
                self.applyEdgeChange(newEdge)
                self.presentImmediately(expanded: false)
                self.expand(suppressPhotoFlight: true)
            }
        case .moveDirectly:
            applyEdgeChange(newEdge)
            presentImmediately(expanded: false)
        }
    }

    private func applyEdgeChange(_ newEdge: DockEdge) {
        edge = newEdge
        silhouette.dockEdge = newEdge
        offset = currentDisplayUUID.map { IslandSettings.dockOffset(forDisplayUUID: $0, edge: newEdge) } ?? 0
        if let currentDisplayUUID { IslandSettings.setDockEdge(newEdge, forDisplayUUID: currentDisplayUUID) }
        currentSize = Self.collapsedSize(for: newEdge, geometry: geometry)
        // See NotchUIState.geometryVersion's own doc comment — without this, switching edges
        // while collapsed (the .moveDirectly case in setDockEdge, which never touches isExpanded
        // or isAnimating) gives SwiftUI no reason to ever re-evaluate CollapsedPill's layout for
        // the new edge, so the old orientation's own background stayed visible until some
        // unrelated render happened to flush it through.
        uiState.geometryVersion += 1
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

    // MARK: - Drag along the edge (collapsed only — design/DESIGN_GUIDE.md §6)

    private func handleDrag(_ delta: CGFloat) {
        guard !uiState.isExpanded else { return }
        let expandedSize = Self.expandedSize(for: edge, geometry: geometry)
        offset = DockPlacement.clampedOffset(
            offset + delta, collapsedSize: currentSize, expandedSize: expandedSize, edge: edge, visibleFrame: visibleFrame
        )
        // A live drag just follows the cursor — no envelope-then-settle animation, the same way
        // dragging any ordinary window doesn't animate.
        let envelope = Self.restingEnvelopeSize(for: currentSize, edge: edge)
        setFrame(windowFrame(for: envelope), display: true)
        if let currentDisplayUUID { IslandSettings.setDockOffset(offset, forDisplayUUID: currentDisplayUUID, edge: edge) }
    }

    // MARK: - Click outside collapses (global monitor); screen-edge strip above a capsule opens it

    /// The thin strip of real menu bar directly above a floating top capsule isn't part of our
    /// own window, so a normal click there never reaches us — only a top capsule needs this; the
    /// other three edges have no such gap to bridge.
    private var screenEdgeClickArea: CGRect? {
        guard edge == .top, let gap = geometry.floatingGap, gap > 0, !uiState.isExpanded, isVisible, !ignoresMouseEvents else { return nil }
        let islandFrame = windowFrame(for: currentSize)
        return CGRect(x: islandFrame.minX, y: islandFrame.maxY, width: islandFrame.width, height: gap + 2)
    }

    private func syncScreenEdgeMonitors() {
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged]
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
        case .leftMouseDragged:
            // A press that moves without leaving the strip does not cancel the click.
            if screenEdgePressed, !area.contains(point) { screenEdgePressed = false }
        default:
            break
        }
    }

    // MARK: - Screen / geometry resolution

    @objc private func screenParametersChanged() {
        reposition()
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

        if nextUUID != currentDisplayUUID {
            // A genuinely different physical display — load *that* display's own saved edge/
            // offset rather than carrying over whatever was in memory for the old one.
            currentDisplayUUID = nextUUID
            edge = nextUUID.map { IslandSettings.dockEdge(forDisplayUUID: $0) } ?? .top
            offset = nextUUID.map { IslandSettings.dockOffset(forDisplayUUID: $0, edge: edge) } ?? 0
            silhouette.dockEdge = edge
        }

        let nextCollapsedSize = Self.collapsedSize(for: edge, geometry: next)
        guard force || next != geometry || visibleFrame != nextVisibleFrame
            || currentSize != (uiState.isExpanded ? Self.expandedSize(for: edge, geometry: next) : nextCollapsedSize)
        else { return }

        geometry = next
        visibleFrame = nextVisibleFrame
        // A resolution/Dock change can push the current offset out of bounds even though the
        // display itself didn't change — re-clamp (never reset to 0) so a drag the user placed
        // deliberately only moves as little as it has to.
        let expandedSizeNow = Self.expandedSize(for: edge, geometry: next)
        offset = DockPlacement.clampedOffset(offset, collapsedSize: nextCollapsedSize, expandedSize: expandedSizeNow, edge: edge, visibleFrame: nextVisibleFrame)
        syncScreenEdgeMonitors()
        // See NotchUIState.geometryVersion's own doc comment — a display/resolution/Dock change
        // can change `edge` (a different display's own saved edge) or `geometry` (notch presence,
        // capsule sizing) without necessarily changing isExpanded, which alone wouldn't give
        // SwiftUI any reason to re-evaluate CollapsedPill/ExpandedCard for the new state.
        uiState.geometryVersion += 1
        presentImmediately(expanded: uiState.isExpanded)
    }

    /// Resets the saved display preference ("Automatic") and re-resolves. Exposed for the
    /// AppKit status-item fallback's "Reset Position" item, so a user stuck with the island
    /// placed on a disconnected/misconfigured display (or just wanting a clean slate) has a way
    /// to recover without digging into Island Settings.
    func resetToDefaultDisplay() {
        logger.info("resetToDefaultDisplay(): clearing saved display preference")
        IslandSettings.chosenDisplayUUID = nil
        reposition()
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

    private static func baseGeometry(for screen: NSScreen?, measurements: MenuBarMeasurements) -> IslandGeometry {
        guard let screen else {
            return IslandGeometry(screen: .zero, safeAreaTop: 0, cameraWidth: 0)
        }
        var measurements = measurements
        let cameraWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else {
            cameraWidth = 0
        }
        let menuBarHeight = measurements.height(
            displayID: screen.notchDisplayID, frame: screen.frame, visibleTop: screen.visibleFrame.maxY,
            scale: screen.backingScaleFactor, statusBarThickness: NSStatusBar.system.thickness
        )
        return IslandGeometry(
            screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top, cameraWidth: cameraWidth,
            menuBarHeight: menuBarHeight, topMargin: IslandSettings.edgeMargin(for: .top)
        )
    }

    /// Only a real physical camera notch hangs flush from the top edge, sized to its own housing
    /// (IslandGeometry.collapsedSize) — every other case, on every edge including a non-notched
    /// top dock, is always CollapsedPill's own plain circle at its configured diameter
    /// (IslandSettings.pillDiameter). The two layers (this native silhouette's size and
    /// CollapsedPill's own SwiftUI content) have to stay in exact lockstep; the "notch" silhouette
    /// simulating a wide cutout here used to produce a visibly different (and differently shaped)
    /// background behind the always-circular SwiftUI pill — owner feedback, not a guess.
    private static func collapsedSize(for edge: DockEdge, geometry: IslandGeometry) -> CGSize {
        (edge == .top && geometry.isNotched) ? geometry.collapsedSize : DockPlacement.collapsedPillSize(for: edge, diameter: IslandSettings.pillDiameter)
    }

    /// The native silhouette's own shape inset for the *collapsed* pill — non-nil (a full circle,
    /// not NotchSilhouetteView's "card" radius) on every edge except a real top-edge camera
    /// notch, which hangs flush instead (IslandGeometry.floatingGap is already nil there). Left/
    /// right/bottom never had an equivalent of IslandGeometry's own notch detection, so they
    /// always get the same small flat inset regardless of what the display reports.
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
    private func windowFrame(for size: CGSize) -> CGRect {
        switch edge {
        case .top:
            var frame = geometry.frame(for: size)
            frame.origin.x += offset
            return frame
        case .bottom, .left, .right:
            return DockPlacement.frame(for: size, edge: edge, offset: offset, visibleFrame: visibleFrame, margin: IslandSettings.edgeMargin(for: edge))
        }
    }

    // MARK: - Present (envelope-then-settle resize)

    /// `suppressPhotoFlight` sets `NotchUIState.isRepositioningEdge` for the duration of this one
    /// swing (cleared again once it settles) — see that property's own doc comment for why an
    /// edge-switch's internal collapse/expand asks for this and an ordinary one doesn't. Every
    /// call sets it fresh, one way or the other, rather than only ever setting it true: that way
    /// a plain (non-suppressing) present() arriving mid-swing — an unrelated collapse/expand that
    /// supersedes this one — always leaves the flag correct for itself, the same reasoning
    /// `presentImmediately` already applies to `isAnimating` below.
    private func present(expanded: Bool, suppressPhotoFlight: Bool = false, completion: @escaping () -> Void = {}) {
        let target = expanded ? Self.expandedSize(for: edge, geometry: geometry) : Self.collapsedSize(for: edge, geometry: geometry)
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
        let envelope = Self.restingEnvelopeSize(for: contentLayoutSize, edge: edge)
        setFrame(windowFrame(for: envelope), display: true)
        layoutContent(for: contentLayoutSize, envelopeSize: envelope)
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
        let targetGap = expanded ? nil : Self.collapsedGap(edge: edge, geometry: geometry)

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
        withAnimation(cardTransitionKind.animation, completionCriteria: .logicallyComplete) {
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
            let restEnvelope = Self.restingEnvelopeSize(for: target, edge: self.edge)
            self.setFrame(self.windowFrame(for: restEnvelope), display: true)
            self.layoutContent(for: target, envelopeSize: restEnvelope)
            // The backdrop reappears here already showing whichever final state (fill color set
            // above, shape) this swing actually ended at.
            self.silhouette.resize(
                to: target, from: target, startGap: targetGap, targetGap: targetGap,
                envelopeSize: restEnvelope, reduceMotion: true, completion: {}
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
        let target = expanded ? Self.expandedSize(for: edge, geometry: geometry) : Self.collapsedSize(for: edge, geometry: geometry)
        currentSize = target
        presentGeneration += 1 // supersede any in-flight animated present()
        // That supersession means an in-flight present()'s own completion handler (the only other
        // place this clears) will never fire — without resetting it here too, interrupting an
        // animated swing with an edge change or a screen change could leave this stuck true
        // forever, hiding the pill even once correctly settled back at rest.
        uiState.isAnimating = false
        // Same reasoning as `isAnimating` just above: nothing is swinging here, so nothing needs
        // to stay suppressed. The one caller that *does* want suppression across this instant
        // reposition (setDockEdge's "move the pill" step, between its collapse and its expand)
        // re-asks for it on its own following `expand(suppressPhotoFlight: true)` call.
        uiState.isRepositioningEdge = false
        silhouette.setFillColor(currentSilhouetteFillColor())
        let restEnvelope = Self.restingEnvelopeSize(for: target, edge: edge)
        setFrame(windowFrame(for: restEnvelope), display: true)
        layoutContent(for: target, envelopeSize: restEnvelope)
        let gap = expanded ? nil : Self.collapsedGap(edge: edge, geometry: geometry)
        silhouette.resize(to: target, from: target, startGap: gap, targetGap: gap, envelopeSize: restEnvelope, reduceMotion: true, completion: {})
    }

    /// Centers the silhouette and the SwiftUI content within the (always at-least-as-large-as-
    /// target, thanks to restingEnvelopeSize's shadow margin even at rest) envelope window.
    ///
    /// `silhouette.resize(...)` also sets its own frame to `envelopeSize` while it's actively
    /// animating, but nothing resets it once the animation finishes and the window shrinks back
    /// down — without doing it here too, the silhouette view stayed sized to the stale, larger
    /// envelope while its parent container shrunk around it, so the shape's internal path
    /// positioning (computed relative to that envelope) ended up off-center in the real window,
    /// clipping its outline unevenly on one side.
    private func layoutContent(for size: CGSize, envelopeSize: CGSize) {
        guard let container = contentView else { return }
        container.frame = NSRect(origin: .zero, size: envelopeSize)
        silhouette.frame = NSRect(origin: .zero, size: envelopeSize)
        hosting.frame = CGRect(origin: contentOrigin(for: size, envelopeSize: envelopeSize), size: size)
    }

    /// Where `size` sits within `envelopeSize`: flush against the docked edge's own side (nothing
    /// needs to render past a flush edge), centered on the perpendicular axis. Mirrors
    /// `restingEnvelopeSize(for:edge:)`'s own margin placement.
    private func contentOrigin(for size: CGSize, envelopeSize: CGSize) -> CGPoint {
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
