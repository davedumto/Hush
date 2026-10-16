import AppKit
import SwiftUI
import os.log

extension NSScreen {
    /// Stable per-display identifier (survives an external monitor being unplugged/reconnected,
    /// unlike CGDirectDisplayID which can be reassigned). nil if unavailable, in which case the
    /// position for that display simply can't be persisted.
    var stableDisplayUUIDString: String? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, uuidRef.takeRetainedValue()) as String
    }
}

/// Borderless, non-activating overlay panel that hosts NotchView. Owns placement (including
/// per-display, option-drag-adjustable position), show/hide, and all expand/collapse interaction
/// (click-to-expand, click-outside-to-collapse, auto-expand on connect with a 4s auto-collapse
/// unless the user interacted).
@MainActor
final class NotchPanel: NSPanel {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "NotchPanel")

    private let headphoneState: HeadphoneState
    private let uiState = NotchUIState()
    let positionState = NotchPositionState()

    private let collapsedDiameter: CGFloat
    private let expandedSize = CGSize(width: 300, height: 120)
    private let collapseAnimationDuration: TimeInterval = 0.4
    private let dragThreshold: CGFloat = 3

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var autoCollapseWorkItem: DispatchWorkItem?

    private var currentDisplayUUID: String?
    private var drag: DragTracker?

    private struct DragTracker {
        let isOptionDrag: Bool
        let startMouseLocation: NSPoint // screen coordinates
        let startPosition: NotchPosition
        var didExceedThreshold = false
    }

    init(headphoneState: HeadphoneState) {
        self.headphoneState = headphoneState
        self.collapsedDiameter = max(NSStatusBar.system.thickness - 4, 10)

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false

        let hosting = NSHostingView(
            rootView: NotchView(state: headphoneState, uiState: uiState, collapsedDiameter: collapsedDiameter)
        )
        contentView = hosting

        reposition()
        installMonitors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
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

    // MARK: - Expand / collapse

    private func expand() {
        guard !uiState.isExpanded else { return }
        uiState.isExpanded = true
        setFrame(forExpanded: true)
    }

    private func collapse() {
        guard uiState.isExpanded else { return }
        uiState.isExpanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + collapseAnimationDuration) { [weak self] in
            guard let self, !self.uiState.isExpanded else { return }
            self.setFrame(forExpanded: false)
        }
    }

    private func scheduleAutoCollapse(after seconds: TimeInterval) {
        autoCollapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.collapse()
        }
        autoCollapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    // MARK: - Position (menu-driven)

    func setPosition(_ position: NotchPosition) {
        guard let screen = currentScreen() else { return }
        let clamped = PositionClamp.clamp(
            position,
            shapeSize: CGSize(width: collapsedDiameter, height: collapsedDiameter),
            displaySize: screen.frame.size
        )
        positionState.position = clamped
        if let uuid = currentDisplayUUID {
            NotchPositionStore.save(clamped, forDisplayUUID: uuid, defaults: .standard)
        }
        setFrame(forExpanded: uiState.isExpanded)
    }

    func resetPosition() {
        guard let screen = currentScreen() else { return }
        if let uuid = currentDisplayUUID {
            NotchPositionStore.reset(forDisplayUUID: uuid, defaults: .standard)
        }
        positionState.position = PositionClamp.clamp(
            defaultPosition(for: screen),
            shapeSize: CGSize(width: collapsedDiameter, height: collapsedDiameter),
            displaySize: screen.frame.size
        )
        setFrame(forExpanded: uiState.isExpanded)
    }

    // MARK: - Placement

    @objc private func screenParametersChanged() {
        reposition()
    }

    func reposition() {
        guard let screen = currentScreen() else { return }
        currentDisplayUUID = screen.stableDisplayUUIDString

        let saved = currentDisplayUUID.flatMap { NotchPositionStore.load(forDisplayUUID: $0, defaults: .standard) }
        let base = saved ?? defaultPosition(for: screen)
        positionState.position = PositionClamp.clamp(
            base,
            shapeSize: CGSize(width: collapsedDiameter, height: collapsedDiameter),
            displaySize: screen.frame.size
        )

        setFrame(forExpanded: uiState.isExpanded)
    }

    private func currentScreen() -> NSScreen? {
        NSScreen.screens.first
    }

    /// Matches the pre-existing placement rule: beside the notch if there is one, otherwise the
    /// old fixed centered default. Only used when no saved position exists for this display.
    private func defaultPosition(for screen: NSScreen) -> NotchPosition {
        if let notch = screen.auxiliaryTopRightArea {
            return NotchPosition(x: Double(notch.minX + 4 - screen.frame.midX), y: 0)
        }
        return .defaultPosition
    }

    private func setFrame(forExpanded expanded: Bool) {
        guard let screen = currentScreen() else { return }
        let displaySize = screen.frame.size
        let collapsedSize = CGSize(width: collapsedDiameter, height: collapsedDiameter)

        if !expanded {
            setFrame(NSRect(origin: appKitOrigin(forLocalTopLeft: localTopLeft(for: positionState.position, displaySize: displaySize), size: collapsedSize, on: screen), size: collapsedSize), display: true)
            return
        }

        // Expanded: horizontally centered under the circle, same top edge (grows downward),
        // then nudged back on-screen if that would clip past an edge.
        let circleLocal = localTopLeft(for: positionState.position, displaySize: displaySize)
        let circleCenterX = circleLocal.x + collapsedSize.width / 2
        let expandedLocal = CGPoint(x: circleCenterX - expandedSize.width / 2, y: circleLocal.y)
        let clampedExpandedLocal = RectClamp.clampOrigin(expandedLocal, size: expandedSize, within: displaySize)

        setFrame(
            NSRect(origin: appKitOrigin(forLocalTopLeft: clampedExpandedLocal, size: expandedSize, on: screen), size: expandedSize),
            display: true
        )
    }

    /// Converts a NotchPosition (offset from display center) to an absolute local top-left point
    /// (0,0 = this display's own top-left, y increasing downward).
    private func localTopLeft(for position: NotchPosition, displaySize: CGSize) -> CGPoint {
        CGPoint(x: displaySize.width / 2 + position.x, y: position.y)
    }

    /// Converts an absolute local top-left point (same convention as above) into the bottom-left
    /// NSRect origin AppKit actually needs, in global desktop coordinates.
    private func appKitOrigin(forLocalTopLeft local: CGPoint, size: CGSize, on screen: NSScreen) -> NSPoint {
        let globalX = screen.frame.minX + local.x
        let topEdgeGlobalY = screen.frame.maxY - local.y
        return NSPoint(x: globalX, y: topEdgeGlobalY - size.height)
    }

    // MARK: - Mouse monitors

    private func installMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.handleOutsideClick()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handleLocalEvent(event)
            return event
        }
    }

    private func handleLocalEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            handleMouseDown(event)
        case .leftMouseDragged:
            handleMouseDragged(event)
        case .leftMouseUp:
            handleMouseUp(event)
        default:
            break
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        guard event.window === self else { return }
        // Repositioning only applies to the collapsed circle, not the expanded card.
        let isOptionDrag = event.modifierFlags.contains(.option) && !uiState.isExpanded
        drag = DragTracker(isOptionDrag: isOptionDrag, startMouseLocation: NSEvent.mouseLocation, startPosition: positionState.position)
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard var tracker = drag else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - tracker.startMouseLocation.x
        let dy = current.y - tracker.startMouseLocation.y

        // Track "did this exceed the click threshold" regardless of the option key, so ANY drag
        // (not just an option-drag) suppresses expand/collapse at mouseUp.
        if !tracker.didExceedThreshold, max(abs(dx), abs(dy)) > dragThreshold {
            tracker.didExceedThreshold = true
        }

        guard tracker.isOptionDrag, tracker.didExceedThreshold, let screen = currentScreen() else {
            drag = tracker
            return
        }

        // AppKit screen Y increases upward; our local position's y increases downward, so a
        // positive on-screen dy (cursor moved up) means the top edge moved up, i.e. position.y decreases.
        let proposed = NotchPosition(x: tracker.startPosition.x + Double(dx), y: tracker.startPosition.y - Double(dy))
        let clamped = PositionClamp.clamp(
            proposed,
            shapeSize: CGSize(width: collapsedDiameter, height: collapsedDiameter),
            displaySize: screen.frame.size
        )
        positionState.position = clamped
        setFrame(forExpanded: false)
        drag = tracker
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard let tracker = drag else { return }
        drag = nil

        if tracker.didExceedThreshold {
            // Any real drag never expands or collapses, regardless of whether option was held.
            if tracker.isOptionDrag, let uuid = currentDisplayUUID {
                NotchPositionStore.save(positionState.position, forDisplayUUID: uuid, defaults: .standard)
            }
            return
        }

        guard event.window === self else { return }
        // Not a drag — behaves as a plain click (option held or not).
        autoCollapseWorkItem?.cancel()
        autoCollapseWorkItem = nil
        if !uiState.isExpanded {
            expand()
        }
        // Click landed inside the already-expanded card: nothing further to do (toggles disabled);
        // cancelling the auto-collapse item above is what keeps it open until an outside click.
    }

    private func handleOutsideClick() {
        guard uiState.isExpanded else { return }
        collapse()
    }
}
