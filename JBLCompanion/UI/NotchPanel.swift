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

    private let silhouette = NotchSilhouetteView(frame: .zero)
    private var hosting: NSHostingView<NotchView>!

    private var geometry: IslandGeometry
    private var currentSize: CGSize
    private var isAnimating = false

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
    private let expandedTopInset: CGFloat = 16

    init(headphoneState: HeadphoneState, onSelectNoiseMode: @escaping (CommandableNoiseMode) -> Void) {
        self.headphoneState = headphoneState
        self.onSelectNoiseMode = onSelectNoiseMode

        let screen = Self.resolveScreen() ?? NSScreen.screens.first
        let initialGeometry = Self.baseGeometry(for: screen, measurements: MenuBarMeasurements())
        self.geometry = initialGeometry
        self.currentSize = initialGeometry.collapsedSize

        super.init(
            contentRect: initialGeometry.frame(for: initialGeometry.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

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
                onSelectNoiseMode: onSelectNoiseMode
            )
        )
        // NSHostingView does not clip its own content to its frame by default — if the SwiftUI
        // content ever wants more room than it's given, it must never visibly spill past the
        // silhouette's edges, even if the size estimate below is ever imperfect.
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true

        let container = NSView(frame: NSRect(origin: .zero, size: initialGeometry.collapsedSize))
        container.wantsLayer = true
        container.addSubview(silhouette)
        container.addSubview(hosting)
        contentView = container

        silhouette.setFloatingGap(initialGeometry.floatingGap)
        silhouette.onTap = { [weak self] in self?.handleTap() }
        silhouette.onHoverChange = { [weak self] hovering in self?.handleHover(hovering) }

        layoutContent(for: initialGeometry.collapsedSize, envelopeSize: initialGeometry.collapsedSize)

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
        let screen = Self.resolveScreen() ?? NSScreen.screens.first
        guard let screen else { return }
        menuBarMeasurements.retainDisplays(NSScreen.screens.map(\.notchDisplayID))
        let next = Self.baseGeometry(for: screen, measurements: menuBarMeasurements)
        guard next != geometry || currentSize != (uiState.isExpanded ? expandedSize(for: next) : next.collapsedSize) else { return }
        geometry = next
        silhouette.setFloatingGap(geometry.floatingGap)
        syncScreenEdgeMonitors()
        present(expanded: uiState.isExpanded)
    }

    private static func resolveScreen() -> NSScreen? {
        if let uuid = IslandSettings.chosenDisplayUUID,
           let chosen = NSScreen.screens.first(where: { $0.stableDisplayUUIDString == uuid }) {
            return chosen
        }
        return NSScreen.screens.first
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

    private func expandedSize(for geometry: IslandGeometry) -> CGSize {
        let width = geometry.expandedWidth
        let contentHeight = measuredExpandedContentHeight(width: width)
        return geometry.expandedSize(contentHeight: contentHeight, topInset: expandedTopInset)
    }

    /// Measures the real height the expanded card's SwiftUI content needs at `width`, instead of
    /// guessing a constant — a throwaway probe view so the live `hosting` view's own state/frame
    /// is never disturbed by the measurement itself.
    private func measuredExpandedContentHeight(width: CGFloat) -> CGFloat {
        let probeState = NotchUIState()
        probeState.isExpanded = true
        let probe = NSHostingView(
            rootView: NotchView(
                state: headphoneState, uiState: probeState, collapsedSize: geometry.collapsedSize,
                onSelectNoiseMode: { _ in }
            )
        )
        probe.frame = CGRect(x: 0, y: 0, width: max(width, 1), height: 1)
        probe.layoutSubtreeIfNeeded()
        let height = probe.fittingSize.height
        guard height.isFinite, height > 0 else { return 150 } // sane fallback if measurement ever fails
        return height
    }

    // MARK: - Present (envelope-then-settle resize)

    private func present(expanded: Bool) {
        uiState.isExpanded = expanded
        let target = expanded ? expandedSize(for: geometry) : geometry.collapsedSize
        guard target != currentSize else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let envelope = IslandMotion.reservation(IslandMotion.envelope(from: currentSize, to: target), centring: target)
        let start = currentSize

        contentRevealWorkItem?.cancel()
        hosting.alphaValue = 0

        // 1. Make the window big enough for the whole swing, then center both views within it.
        setFrame(geometry.frame(for: envelope), display: true)
        layoutContent(for: start, envelopeSize: envelope)

        isAnimating = true
        silhouette.resize(to: target, from: start, envelopeSize: envelope, reduceMotion: reduceMotion) { [weak self] in
            guard let self else { return }
            self.isAnimating = false
            self.currentSize = target
            // 2. Settle the window back down to exactly the target size.
            self.setFrame(self.geometry.frame(for: target), display: true)
            self.layoutContent(for: target, envelopeSize: target)
            self.revealContent()
        }
    }

    /// Centers the silhouette and the SwiftUI content within the (possibly larger-than-target)
    /// envelope window, both using the same size for now — content stays hidden until the shape
    /// settles (see `revealContent`), so a mid-resize mismatch is never visible.
    private func layoutContent(for size: CGSize, envelopeSize: CGSize) {
        guard let container = contentView else { return }
        container.frame = NSRect(origin: .zero, size: envelopeSize)
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
