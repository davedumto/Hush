import AppKit
import QuartzCore

/// Renders and animates the island's own silhouette (a CAShapeLayer, not SwiftUI), hit-tests
/// against that exact path so clicks in the empty part of the window pass through to whatever's
/// beneath, and reports taps/hover on the shape. Ported from vorssaint-utils's silhouette
/// animation (NotchWindowHost.swift ~1321-1365) and `hitTest` (~1293).
final class NotchSilhouetteView: NSView {
    private static let motionKey = "islandResize"

    private let shapeLayer = CAShapeLayer()
    private var animationGeneration = 0
    private var pressedInside = false
    private var hoverTrackingArea: NSTrackingArea?

    var onTap: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    /// Whether a drag is currently allowed at all (the panel says no while expanded) — checked
    /// once a real drag is detected, before the manual tracking below takes over.
    var canDrag: (() -> Bool)?
    /// Called on every drag tick with the window's own next *envelope* origin, computed from the
    /// raw mouse delta — before this view applies it. Returns the origin to actually use, letting
    /// the panel clamp live against the real screen boundary (not just once at drop time) — see
    /// `mouseDragged`'s own doc comment for why this has to happen here, not via
    /// `performDrag`/`NSWindow.didMoveNotification`.
    var clampOrigin: ((CGPoint) -> CGPoint)?
    /// Fires once, right after a real drag (not a plain tap) finishes — the window has already
    /// been moved to its final position by the time this fires; the panel's cue to decide whether
    /// the drag ended close enough to a screen edge to dock there, or far enough away to settle
    /// into free placement.
    var onDragEnd: (() -> Void)?
    /// Only used for the shape's own flush-to-edge rendering (`resize(...)`'s `symmetric: false`
    /// branch). Set by the caller whenever the dock edge changes. Defaults to `.top`, matching
    /// this view's original top-only behavior.
    var dockEdge: DockEdge = .top
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

    // Tracked by hand, inside a synchronous `window.nextEvent(...)` loop, rather than relying on
    // the normal asynchronous mouseDragged/mouseUp responder dispatch, and rather than handing the
    // gesture off to `window.performDrag(with:)`.
    //
    // `performDrag` was tried first and rejected: it hands the whole gesture to AppKit's own
    // drag loop, which gives no hook to intervene while it's running, so a free-floating drop near
    // a screen edge visibly jumped once it finished (the only place left to correct it was after
    // the fact).
    //
    // The normal per-event `mouseDragged`/`mouseUp` override approach was tried next and also
    // rejected: a real `log stream` capture (free-drag investigation) showed `mouseDragged` ticks
    // arriving steadily, then going silent mid-gesture — no further ticks and no `mouseUp` at all
    // — away from any screen edge or clamp, i.e. AppKit itself dropped the rest of the gesture's
    // dispatch. This is a known failure mode for a window that
    // can never become key (`NotchPanel.canBecomeKey == false`, deliberate — the panel must never
    // steal focus): normal event dispatch for such a window isn't guaranteed to keep delivering a
    // fast-moving drag all the way to its `mouseUp`.
    //
    // Running a tight, synchronous `nextEvent(matching:until:inMode:dequeue:)` loop inside
    // `mouseDown` — the standard AppKit idiom for dragging a non-activating utility window/status
    // item (used by menu-bar extras generally) — sidesteps that: it dequeues drag/up events
    // directly from the event queue in `.eventTracking` run-loop mode instead of waiting for the
    // normal asynchronous responder-chain dispatch that was silently dying here, so there is
    // nothing left in the delivery path for a fast motion to fall out of.
    override func mouseDown(with event: NSEvent) {
        pressedInside = true
        guard let window else { return }
        // Global screen coordinates, not `event.locationInWindow` — the window itself moves on
        // every drag tick below, which would shift locationInWindow's own coordinate space out
        // from under the cursor mid-drag and compound into a small feedback error each tick (the
        // window chasing a reference point that itself keeps moving). NSEvent.mouseLocation is
        // screen-space and unaffected by this view's own window moving.
        let anchor = NSEvent.mouseLocation
        var anchorWindowOrigin: CGPoint?
        didDrag = false

        trackingLoop: while true {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture,
                inMode: .eventTracking, dequeue: true
            ) else { break }

            switch next.type {
            case .leftMouseDragged:
                // A press that moves without leaving the shape does not cancel the click; only
                // leaving it does.
                let point = convert(next.locationInWindow, from: nil)
                pressedInside = shapeLayer.path?.contains(point) ?? false
                let current = NSEvent.mouseLocation

                if !didDrag {
                    guard DockPlacement.isDrag(from: anchor, to: current) else { continue trackingLoop }
                    guard canDrag?() ?? true else { continue trackingLoop }
                    didDrag = true
                    anchorWindowOrigin = window.frame.origin
                }

                guard let anchorOrigin = anchorWindowOrigin else { continue trackingLoop }
                let rawOrigin = CGPoint(
                    x: anchorOrigin.x + (current.x - anchor.x), y: anchorOrigin.y + (current.y - anchor.y)
                )
                let finalOrigin = clampOrigin?(rawOrigin) ?? rawOrigin
                window.setFrameOrigin(finalOrigin)
                pressedInside = false

            case .leftMouseUp:
                let wasPressed = pressedInside
                pressedInside = false
                if didDrag {
                    didDrag = false
                    onDragEnd?()
                } else if wasPressed {
                    let point = convert(next.locationInWindow, from: nil)
                    if shapeLayer.path?.contains(point) ?? false { onTap?() }
                }
                break trackingLoop

            default:
                break
            }
        }
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
        envelopeSize: CGSize, symmetric: Bool = false, reduceMotion: Bool, completion: @escaping () -> Void
    ) {
        animationGeneration += 1
        let generation = animationGeneration

        frame = CGRect(origin: .zero, size: envelopeSize)
        shapeLayer.frame = CGRect(origin: .zero, size: envelopeSize)

        // Flush against the docked edge's own side (nothing needs to render past a flush edge),
        // centered on the perpendicular axis — mirrors NotchPanel.contentOrigin(for:envelopeSize:)
        // exactly, which is what keeps this native shape and the real SwiftUI content on top of
        // it in the same place. This used to be hardcoded to "flush top, centered horizontally"
        // unconditionally; that was fine when `.top` was the only reachable dock, but left the
        // shape itself (and its hit-testing) pinned to the top of the window on every other edge
        // even after the SwiftUI content moved to the real docked edge.
        //
        // `symmetric` (the collapsed pill's own settled state only — see NotchPanel.layoutContent's
        // own doc comment) centers on *both* axes instead: flush-against-the-edge, by design, left
        // the pill with zero envelope room on the near/docked side for its own hover-scale growth
        // (MotionConstants.pillHoverScale) and shadow/glow to bleed into, clipping flat against the
        // window's own hard edge on hover — a "chip" on whichever side faces the docked edge.
        func origin(for size: CGSize) -> CGPoint {
            guard !symmetric else {
                return CGPoint(x: (envelopeSize.width - size.width) / 2, y: (envelopeSize.height - size.height) / 2)
            }
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
        // The fill is never allowed to sit flush with 0 — there's always at least this much
        // margin, regardless of floating-gap state, so nothing renders exactly at the view's own
        // pixel edge (antialiasing/clipping artifacts there, not a stroke's own clearance — this
        // native layer no longer draws one at all; see ExpandedCard.frame's own doc comment).
        let minimumEdgeMargin: CGFloat = 0.5
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
        func fillPath(for size: CGSize, at t: Double) -> CGPath {
            let (inset, radius) = insetAndRadius(for: size, at: t)
            return translated(IslandShape.path(size: size, inset: inset, cornerRadius: radius), for: size)
        }

        if reduceMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.path = fillPath(for: target, at: 1)
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
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, generation == self.animationGeneration else { return }
            self.shapeLayer.removeAnimation(forKey: Self.motionKey)
            completion()
        }
    }
}
