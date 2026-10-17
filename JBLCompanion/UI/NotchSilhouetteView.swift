import AppKit
import QuartzCore

/// Renders and animates the island's own silhouette (a CAShapeLayer, not SwiftUI), hit-tests
/// against that exact path so clicks in the empty part of the window pass through to whatever's
/// beneath, and reports taps/hover on the shape. Ported from vorssaint-utils's silhouette
/// animation (NotchWindowHost.swift ~1321-1365) and `hitTest` (~1293).
final class NotchSilhouetteView: NSView {
    private static let motionKey = "islandResize"

    private let shapeLayer = CAShapeLayer()
    /// Traces the exact same path as `shapeLayer`, stroked — the brand-accent outline around the
    /// island, kept in sync through every animation frame rather than drawn separately in SwiftUI,
    /// since only the native layer actually knows the live shape mid-resize.
    private let edgeLayer = CAShapeLayer()
    private var animationGeneration = 0
    private var pressedInside = false
    private var hoverTrackingArea: NSTrackingArea?

    var onTap: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    /// design/DESIGN_GUIDE.md §6: "the pill can be dragged along its edge only" — reports the
    /// incremental delta (not cumulative from the original mouseDown) along whichever axis
    /// `dockEdge` implies, so the panel can just add it straight onto its current offset. Only
    /// fires once the move exceeds DockPlacement.dragThreshold ("a click that moves less than a
    /// few points is a click, not a drag") — before that, this stays silent and `onTap` still
    /// fires normally on mouseUp.
    var onDrag: ((CGFloat) -> Void)?
    /// Which axis `onDrag` reports deltas along — set by the caller whenever the dock edge
    /// changes. Defaults to `.top` (horizontal), matching this view's original top-only behavior.
    var dockEdge: DockEdge = .top
    private var dragAnchor: CGPoint?
    private var didDrag = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // A stroke centers on its path, so stroking the fill's own path directly puts half the
        // line outside the fill shape. Rather than hand-computing an inset path (fragile for
        // rounded rects — getting the corner-radius reduction exactly right is easy to get
        // slightly wrong, which is what caused the outline to visibly overshoot the fill), clip
        // this view's layer to its own bounds and let that cut away whatever falls outside —
        // the same effect, achieved by the compositor instead of by hand.
        layer?.masksToBounds = true
        shapeLayer.fillColor = NSColor.black.cgColor
        layer?.addSublayer(shapeLayer)
        // Default is black because that was the only color this silhouette ever needed before the
        // hush. restyle, which made both the pill and the card's own frame theme-aware (white in
        // light, black in dark) — see `setFillColor`.

        edgeLayer.fillColor = nil
        edgeLayer.strokeColor = nil // starts hidden — see setEdgeVisible; collapsed never shows it.
        edgeLayer.lineWidth = 1.5
        layer?.addSublayer(edgeLayer)
    }

    private static let edgeOrange = NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.05, alpha: 0.9).cgColor

    /// The orange outline is a card-only accent (ExpandedCard draws its own copy of it once real
    /// content is showing — see that view's own doc comment) — the collapsed pill has its own,
    /// much subtler SwiftUI-level border (CollapsedPill's `borderColor`) and was never meant to
    /// show this orange one at all. Call before every resize, same as `setFillColor`, so the
    /// stroke is already in the right state for the whole swing, not just once it settles.
    func setEdgeVisible(_ visible: Bool) {
        let target: CGColor? = visible ? Self.edgeOrange : nil
        guard edgeLayer.strokeColor != target else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeLayer.strokeColor = target
        CATransaction.commit()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard let path = shapeLayer.path, path.contains(local) else { return nil }
        return self
    }

    /// Set before a resize, never mid-animation — this native fill is the backdrop the SwiftUI
    /// content (CollapsedPill/ExpandedCard, both visible and animating throughout the swing — see
    /// NotchView's own `.transition`) sits on top of for the whole pill<->card swing. Without
    /// matching it to the real theme ahead of time, light theme's white card used to visibly flash
    /// black first (the stale default), then "transition" to white once content caught up.
    func setFillColor(_ color: NSColor) {
        guard shapeLayer.fillColor != color.cgColor else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.fillColor = color.cgColor
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        pressedInside = true
        dragAnchor = event.locationInWindow
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        // A press that moves without leaving the shape does not cancel the click; only leaving it does.
        let point = convert(event.locationInWindow, from: nil)
        pressedInside = shapeLayer.path?.contains(point) ?? false

        guard let anchor = dragAnchor else { return }
        let current = event.locationInWindow
        if !didDrag {
            guard DockPlacement.isDrag(from: anchor, to: current) else { return }
            didDrag = true
        }
        let delta = dockEdge.isVertical ? (current.y - anchor.y) : (current.x - anchor.x)
        dragAnchor = current
        onDrag?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressedInside
        pressedInside = false
        dragAnchor = nil
        // A drag is never a click, even if the cursor ends up back inside the shape.
        guard !didDrag else { didDrag = false; return }
        guard wasPressed else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard shapeLayer.path?.contains(point) ?? false else { return }
        onTap?()
    }

    /// Resizes the shape from `start` to `target` within a window already sized to
    /// `envelopeSize` (the largest the shape gets mid-swing, including overshoot). `startGap`/
    /// `targetGap` are the floating-gap values (nil = attached/flush, the normal rounded-card
    /// shape) at each end — e.g. the collapsed capsule's gap at one end and nil at the other,
    /// since the capsule's pill shape only ever applies to the small resting indicator, never to
    /// the wide expanded card. Both the inset (gap) AND the corner radius are linearly
    /// interpolated between the two ends across the resize — interpolating the radius matters
    /// just as much as the gap: a capsule's radius is height/2 (a true pill), so without easing
    /// the radius itself down too, the shape stays pill-shaped for most of the growth even once
    /// it's already wide. Calls `completion` once the resize has settled (or immediately,
    /// unanimated, under Reduce Motion).
    func resize(
        to target: CGSize, from start: CGSize, startGap: CGFloat?, targetGap: CGFloat?,
        envelopeSize: CGSize, reduceMotion: Bool, completion: @escaping () -> Void
    ) {
        animationGeneration += 1
        let generation = animationGeneration

        frame = CGRect(origin: .zero, size: envelopeSize)
        shapeLayer.frame = CGRect(origin: .zero, size: envelopeSize)
        edgeLayer.frame = CGRect(origin: .zero, size: envelopeSize)

        // Flush against the docked edge's own side (nothing needs to render past a flush edge),
        // centered on the perpendicular axis — mirrors NotchPanel.contentOrigin(for:envelopeSize:)
        // exactly, which is what keeps this native shape and the real SwiftUI content on top of
        // it in the same place. This used to be hardcoded to "flush top, centered horizontally"
        // unconditionally; that was fine when `.top` was the only reachable dock, but left the
        // shape itself (and its hit-testing) pinned to the top of the window on every other edge
        // even after the SwiftUI content moved to the real docked edge.
        func origin(for size: CGSize) -> CGPoint {
            switch dockEdge {
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
        // 0 = flush card shape, 1 = full pill — interpolated continuously, not switched at a threshold.
        let startPillness: Double = startGap != nil ? 1 : 0
        let targetPillness: Double = targetGap != nil ? 1 : 0
        // A stroke centers on its path: half of edgeLayer.lineWidth needs to fit *outside* the
        // fill's own boundary without hitting the view's literal edge. vorssaint's real outline
        // doesn't fight this — it reserves actual room for the outline in its geometry, so the
        // fill is never flush with the window edge in the first place, even when "attached."
        // Same idea here: the fill is never allowed to sit flush with 0 — there's always at
        // least this much margin, regardless of floating-gap state, so the stroke always has
        // somewhere to live.
        let minimumEdgeMargin = edgeLayer.lineWidth / 2 + 0.5
        func insetAndRadius(for size: CGSize, at t: Double) -> (inset: CGFloat, radius: CGFloat) {
            let pillness = CGFloat(startPillness + (targetPillness - startPillness) * t)
            let rawInset = (startGap ?? 0) + ((targetGap ?? 0) - (startGap ?? 0)) * CGFloat(t)
            let inset = max(rawInset, minimumEdgeMargin)
            let cardRadius = IslandShape.cardRadius(height: size.height)
            let pillRadius = IslandShape.pillRadius(height: size.height)
            return (inset, cardRadius + (pillRadius - cardRadius) * pillness)
        }
        func translated(_ raw: CGPath, for size: CGSize) -> CGPath {
            var transform = CGAffineTransform(translationX: origin(for: size).x, y: origin(for: size).y)
            return raw.copy(using: &transform) ?? raw
        }
        // The edge stroke uses this exact same path as the fill — with the minimum margin above,
        // the stroke always fits inside the view's own bounds without needing separate inset math.
        func fillPath(for size: CGSize, at t: Double) -> CGPath {
            let (inset, radius) = insetAndRadius(for: size, at: t)
            return translated(IslandShape.path(size: size, inset: inset, cornerRadius: radius), for: size)
        }

        if reduceMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let path = fillPath(for: target, at: 1)
            shapeLayer.path = path
            edgeLayer.path = path
            CATransaction.commit()
            completion()
            return
        }

        let (sizes, keyTimes, duration) = IslandMotion.frames(from: start, to: target)
        let fillPaths = zip(sizes, keyTimes).map { fillPath(for: $0, at: $1) }

        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = fillPaths
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = duration
        animation.setValue(generation, forKey: "islandGeneration")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = fillPaths.last
        shapeLayer.add(animation, forKey: Self.motionKey)
        edgeLayer.path = fillPaths.last
        if let edgeAnimation = animation.copy() as? CAKeyframeAnimation {
            edgeAnimation.delegate = nil
            edgeLayer.add(edgeAnimation, forKey: Self.motionKey)
        }
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, generation == self.animationGeneration else { return }
            self.shapeLayer.removeAnimation(forKey: Self.motionKey)
            self.edgeLayer.removeAnimation(forKey: Self.motionKey)
            completion()
        }
    }
}
