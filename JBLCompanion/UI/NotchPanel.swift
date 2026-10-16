import AppKit
import SwiftUI
import os.log

extension UserDefaults {
    private static let notchOffsetKey = "notchOffset"

    /// Horizontal offset (points) from screen center used when the display has no notch.
    /// Live-adjustable because Vorssaint also draws at top-center and the two must not collide.
    var notchOffset: Double {
        get {
            object(forKey: Self.notchOffsetKey) == nil ? 140 : double(forKey: Self.notchOffsetKey)
        }
        set { set(newValue, forKey: Self.notchOffsetKey) }
    }
}

/// Borderless, non-activating overlay panel that hosts NotchView. Owns placement, show/hide,
/// and all expand/collapse interaction (click-to-expand, click-outside-to-collapse, auto-expand
/// on connect with a 4s auto-collapse unless the user interacted).
@MainActor
final class NotchPanel: NSPanel {
    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "NotchPanel")

    private let headphoneState: HeadphoneState
    private let uiState = NotchUIState()

    private let collapsedDiameter: CGFloat
    private let expandedSize = CGSize(width: 300, height: 120)
    private let collapseAnimationDuration: TimeInterval = 0.4

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var autoCollapseWorkItem: DispatchWorkItem?

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

    // MARK: - Placement

    @objc private func screenParametersChanged() {
        reposition()
    }

    func reposition() {
        setFrame(forExpanded: uiState.isExpanded)
    }

    private func setFrame(forExpanded expanded: Bool) {
        guard let screen = NSScreen.screens.first else { return }

        let size = expanded ? expandedSize : CGSize(width: collapsedDiameter, height: collapsedDiameter)
        let menuBarHeight = NSStatusBar.system.thickness
        let topY = screen.frame.maxY

        let x: CGFloat
        if let notch = screen.auxiliaryTopRightArea {
            x = notch.minX + 4
        } else {
            x = screen.frame.midX + UserDefaults.standard.notchOffset
        }

        // Anchored to the top of the menu bar row; expanding grows downward from there.
        let anchorTopY = topY
        let origin = CGPoint(x: x, y: anchorTopY - size.height)
        _ = menuBarHeight // retained for future vertical centering tweaks; top-anchored for now.

        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: - Mouse monitors

    private func installMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.handleOutsideClick()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleLocalClick(event)
            return event
        }
    }

    private func handleLocalClick(_ event: NSEvent) {
        guard event.window === self else { return }
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
