import AppKit
import SwiftUI
import os.log

extension NSScreen {
    /// Stable per-display identifier (survives an external monitor being unplugged/reconnected,
    /// unlike CGDirectDisplayID which can be reassigned). Used only for the "chosen display"
    /// setting — nothing here is positioned per-display anymore.
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
/// envelope-then-settle resize, hover open/close, and the screen-edge click area for a floating
/// capsule) — no dragging, no per-display saved position; the island is fixed, centered on the
/// menu-bar display, pinned to its top edge.
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

    private let silhouette = NotchSilhouetteView(frame: .zero)
    private var hosting: NSHostingView<NotchView>!

    private var geometry: IslandGeometry
    private var currentSize: CGSize
    private var isAnimating = false
    /// Bumped on every present() call; a stale completion whose generation no longer matches is
    /// dropped instead of applying its (now outdated) frame/content, which is what let a
    /// superseded transition leave the window sized for one state while content rendered for
    /// another — an oversized, seemingly empty shape.
    private var presentGeneration = 0

    private var menuBarMeasurements = MenuBarMeasurements()
    private var globalMouseMonitor: Any?
    private var screenEdgeMonitors: [Any] = []
    private var screenEdgePressed = false
    private var autoCollapseWorkItem: DispatchWorkItem?
    private var hoverOpenWorkItem: DispatchWorkItem?
    private var hoverCloseWorkItem: DispatchWorkItem?
    private var contentRevealWorkItem: DispatchWorkItem?

    private let hoverOpenDelay: TimeInterval = 0.15
    private let hoverCloseDelay: TimeInterval = 0.4
    /// Extra transparent room reserved, at rest, around both the pill and the card so their own
    /// shadows/glows (CollapsedPill, ExpandedCard — both reach past their own bounds) aren't
    /// clipped by the window's edge. Symmetric on the sides; reserved below only, since nothing
    /// needs to render above a top-anchored shape. Deliberately a flat constant, not computed
    /// from the real shadow radii — kept minimal pending full edge docking.
    private static let shadowMargin: CGFloat = 40

    private static func restingEnvelopeSize(for contentSize: CGSize) -> CGSize {
        CGSize(width: contentSize.width + shadowMargin * 2, height: contentSize.height + shadowMargin)
    }

    /// ExpandedCard's own fixed size (design/DESIGN_GUIDE.md §4/§10) — only the top dock is live
    /// today (see ExpandedCard's own doc comment), so this is always the horizontal-dock width.
    /// A real constant, not a measurement: unlike the old variable-content card this replaced,
    /// ExpandedCard's height of 470 is fixed regardless of what it's showing, so there's nothing
    /// to measure — see `expandedSize(for:)`'s own doc comment for why measuring it anyway
    /// (the previous approach here) was actively wrong, not just redundant.
    private static let expandedCardWidth: CGFloat = 374
    private static let expandedCardHeight: CGFloat = 470

    init(
        headphoneState: HeadphoneState, onSelectNoiseMode: @escaping (CommandableNoiseMode) -> Void,
        isModeVerified: @escaping (CommandableNoiseMode) -> Bool,
        supportsNoiseControl: @escaping () -> Bool
    ) {
        self.headphoneState = headphoneState
        self.onSelectNoiseMode = onSelectNoiseMode
        self.isModeVerified = isModeVerified
        self.supportsNoiseControl = supportsNoiseControl

        let resolution = Self.resolveScreen()
        let screen = resolution.screen
        let initialGeometry = Self.baseGeometry(for: screen, measurements: MenuBarMeasurements())
        self.geometry = initialGeometry
        self.currentSize = initialGeometry.collapsedSize

        super.init(
            contentRect: initialGeometry.frame(for: Self.restingEnvelopeSize(for: initialGeometry.collapsedSize)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        Self.logDisplayResolution(resolution, logger: logger)
        logger.info("NotchPanel created. frame=\(NSStringFromRect(self.frame), privacy: .public)")

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.normalLevel
        collectionBehavior = Self.overlayCollectionBehavior
        isMovable = false
        isReleasedWhenClosed = false

        hosting = NSHostingView(
            rootView: NotchView(
                state: headphoneState, uiState: uiState, collapsedSize: initialGeometry.collapsedSize,
                onSelectNoiseMode: onSelectNoiseMode, isModeVerified: isModeVerified,
                supportsNoiseControl: supportsNoiseControl, isNotched: { [weak self] in self?.isNotched ?? false },
                onCollapseTabTapped: { [weak self] in self?.handleTabTap() }
            )
        )
        // NSHostingView does not clip its own content to its frame by default. `hosting` itself
        // stays sized to the pill/card's own exact content size (unchanged, still positioned by
        // the same origin math below) — the surrounding `container` is the one sized to the
        // margined envelope, so CollapsedPill/ExpandedCard's own shadows have real window room to
        // bleed into. masksToBounds stays off deliberately: it would clip that intentional
        // overflow right back off, same as it would an oversized estimate.
        hosting.wantsLayer = true

        let initialEnvelope = Self.restingEnvelopeSize(for: initialGeometry.collapsedSize)
        let container = NSView(frame: NSRect(origin: .zero, size: initialEnvelope))
        container.wantsLayer = true
        container.addSubview(silhouette)
        container.addSubview(hosting)
        contentView = container

        silhouette.onTap = { [weak self] in self?.handleTap() }
        silhouette.onHoverChange = { [weak self] hovering in self?.handleHover(hovering) }

        layoutContent(for: initialGeometry.collapsedSize, envelopeSize: initialEnvelope)
        silhouette.setFillColor(currentSilhouetteFillColor())
        // Give the silhouette an initial path immediately — otherwise it stays empty (zero
        // frame) until the first expand/collapse transition ever runs.
        silhouette.resize(
            to: initialGeometry.collapsedSize, from: initialGeometry.collapsedSize,
            startGap: initialGeometry.floatingGap, targetGap: initialGeometry.floatingGap,
            envelopeSize: initialEnvelope, reduceMotion: true, completion: {}
        )

        installMonitors()
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
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
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
        expand()
        scheduleAutoCollapse(after: 4)
    }

    func handleClassicDisconnected() {
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        collapse()
    }

    // MARK: - Settings changed (size/silhouette/fits/outline/display)

    var isNotched: Bool { geometry.isNotched }

    func settingsDidChange() {
        reposition()
    }

    // MARK: - Expand / collapse

    private func expand() {
        guard !uiState.isExpanded else { return }
        present(expanded: true)
    }

    private func collapse() {
        guard uiState.isExpanded else { return }
        present(expanded: false)
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

    // MARK: - Hover open/close (delayed, so it doesn't flicker at the edge)

    private func handleHover(_ hovering: Bool) {
        if hovering {
            hoverCloseWorkItem?.cancel()
            hoverCloseWorkItem = nil
            guard !uiState.isExpanded else { return }
            let item = DispatchWorkItem { [weak self] in self?.expand() }
            hoverOpenWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverOpenDelay, execute: item)
        } else {
            hoverOpenWorkItem?.cancel()
            hoverOpenWorkItem = nil
            guard uiState.isExpanded else { return }
            let item = DispatchWorkItem { [weak self] in self?.collapse() }
            hoverCloseWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + hoverCloseDelay, execute: item)
        }
    }

    // MARK: - Click outside collapses (global monitor); screen-edge strip above a capsule opens it

    private func installMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.handleOutsideClick() }
        }
    }

    private func handleOutsideClick() {
        guard uiState.isExpanded else { return }
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        collapse()
    }

    /// The thin strip of real menu bar directly above a floating capsule isn't part of our own
    /// window, so a normal click there never reaches us — only a capsule needs this.
    private var screenEdgeClickArea: CGRect? {
        guard let gap = geometry.floatingGap, gap > 0, !uiState.isExpanded, isVisible, !ignoresMouseEvents else { return nil }
        let size = geometry.collapsedSize
        let islandFrame = geometry.frame(for: size)
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

    func reposition() {
        let resolution = Self.resolveScreen()
        Self.logDisplayResolution(resolution, logger: logger)
        guard let screen = resolution.screen else {
            logger.error("reposition(): no display available; keeping current geometry")
            return
        }
        menuBarMeasurements.retainDisplays(NSScreen.screens.map(\.notchDisplayID))
        let next = Self.baseGeometry(for: screen, measurements: menuBarMeasurements)
        guard next != geometry || currentSize != (uiState.isExpanded ? expandedSize(for: next) : next.collapsedSize) else { return }
        geometry = next
        syncScreenEdgeMonitors()
        present(expanded: uiState.isExpanded)
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
            layout: IslandSettings.size, menuBarHeight: menuBarHeight,
            customWidth: IslandSettings.customWidth, customHeight: IslandSettings.customHeight,
            cameraFit: IslandSettings.cameraFit, silhouette: IslandSettings.silhouette,
            capsuleFit: IslandSettings.capsuleFit, hideMenuBarGap: IslandSettings.hideMenuBarGap,
            outline: IslandSettings.outlineEnabled
        )
    }

    /// ExpandedCard's own fixed 374x470 (design/DESIGN_GUIDE.md §10), capped against the real
    /// screen's bounds for safety on a small/unusual display — not measured, since (unlike the
    /// old variable-content card this replaced) that size no longer depends on what the card is
    /// actually showing. Measuring it anyway, via a throwaway NSHostingView probe's `fittingSize`,
    /// is what this function used to do — and it was actively wrong, not just redundant: that
    /// probe path wasn't exercised by the snapshot-harness comparison (ImageRenderer renders each
    /// scenario directly, never through `fittingSize`), so it shipped seemingly verified while
    /// actually under-measuring the card's real height — the window came out too short, and
    /// content size, which is taken as 100% correct, is being assigned its own documented size
    /// (470 tall) inside the too-short envelope regardless, pushing the top of the card (and the
    /// whole top row) up past the window's own top edge where nothing is visible to render it.
    private func expandedSize(for geometry: IslandGeometry) -> CGSize {
        let width = min(Self.expandedCardWidth, geometry.screen.width - 24)
        let height = min(Self.expandedCardHeight, geometry.screen.height - 48)
        return CGSize(width: width, height: max(80, height))
    }

    // MARK: - Present (envelope-then-settle resize)

    private func present(expanded: Bool) {
        uiState.isExpanded = expanded
        let target = expanded ? expandedSize(for: geometry) : geometry.collapsedSize
        guard target != currentSize else {
            // Nothing to animate — but make sure content is actually visible, in case an earlier,
            // now-superseded transition left it hidden mid-fade.
            hosting.animator().alphaValue = 1
            return
        }

        presentGeneration += 1
        let generation = presentGeneration

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let envelope = IslandMotion.reservation(IslandMotion.envelope(from: currentSize, to: target), centring: target)
        let start = currentSize
        // Updated immediately (not just on completion) so a second present() call arriving before
        // this one finishes compares against where we're actually headed, not the stale
        // pre-animation size — that staleness is what let a superseded transition's completion
        // leave the window sized for the wrong state.
        currentSize = target

        contentRevealWorkItem?.cancel()
        hosting.alphaValue = 0
        // Set before the swing starts, not after: the native fill is what's actually on screen
        // for most of the animation (SwiftUI content stays hidden until revealContent), so it
        // has to already be correct, not just end up correct once the real content fades in.
        silhouette.setFillColor(currentSilhouetteFillColor())

        // 1. Make the window big enough for the whole swing, then center both views within it.
        setFrame(geometry.frame(for: envelope), display: true)
        layoutContent(for: start, envelopeSize: envelope)

        // The capsule's rounded-pill shape only ever belongs to the small collapsed indicator —
        // the wide expanded card is always a plain rounded rectangle (gap nil), regardless of
        // which silhouette is chosen for the collapsed state.
        let startGap = expanded ? geometry.floatingGap : nil
        let targetGap = expanded ? nil : geometry.floatingGap

        isAnimating = true
        silhouette.resize(
            to: target, from: start, startGap: startGap, targetGap: targetGap,
            envelopeSize: envelope, reduceMotion: reduceMotion
        ) { [weak self] in
            guard let self, generation == self.presentGeneration else { return }
            self.isAnimating = false
            // 2. Settle the window back down to the target size, plus the resting shadow margin
            // (restingEnvelopeSize) — not exactly the target, or CollapsedPill/ExpandedCard's own
            // shadows would have nowhere to bleed into and clip right back at the window edge.
            let restEnvelope = Self.restingEnvelopeSize(for: target)
            self.setFrame(self.geometry.frame(for: restEnvelope), display: true)
            self.layoutContent(for: target, envelopeSize: restEnvelope)
            // Shrinking silhouette's frame above does NOT rescale/reposition its existing path —
            // that path was computed relative to the larger envelope frame it had while
            // animating, so left alone it now sits offset toward one corner of the new, smaller
            // frame instead of filling it, pushing the shape (and its outline) past the edge on
            // whichever sides that offset points toward. Snapping it again, unanimated, at the
            // final size recomputes the path for the frame it actually has now.
            self.silhouette.resize(
                to: target, from: target, startGap: targetGap, targetGap: targetGap,
                envelopeSize: restEnvelope, reduceMotion: true, completion: {}
            )
            self.revealContent()
        }
    }

    /// Centers the silhouette and the SwiftUI content within the (always at-least-as-large-as-
    /// target, thanks to restingEnvelopeSize's shadow margin even at rest) envelope window —
    /// content stays hidden until the shape settles (see `revealContent`), so a mid-resize
    /// mismatch is never visible.
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
        let origin = CGPoint(x: (envelopeSize.width - size.width) / 2, y: envelopeSize.height - size.height)
        hosting.frame = CGRect(origin: origin, size: size)
    }

    /// Content swaps during a brief hidden window, then fades in once the shape has settled.
    private func revealContent() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hosting.animator().alphaValue = 1
        }
        contentRevealWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }
}
