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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        shapeLayer.fillColor = NSColor.black.cgColor
        layer?.addSublayer(shapeLayer)

        edgeLayer.fillColor = nil
        edgeLayer.strokeColor = NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.05, alpha: 0.9).cgColor
        edgeLayer.lineWidth = 1.5
        layer?.addSublayer(edgeLayer)
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

    /// A stroke centers on its path, so stroking the fill shape's own path directly would let
    /// half the line extend past the view's bounds — invisible (clipped by the window) exactly
    /// like the menu panel's border was before switching to strokeBorder. Building the edge from
    /// a path inset by an extra half line-width keeps the entire stroke inside the fill shape,
    /// so its outer edge lines up with the fill's boundary instead of overshooting it.
    private func edgePath(size: CGSize, inset: CGFloat, cornerRadius: CGFloat) -> CGPath {
        let extra = edgeLayer.lineWidth / 2
        return IslandShape.path(size: size, inset: inset + extra, cornerRadius: max(0, cornerRadius - extra))
    }

    override func mouseDown(with event: NSEvent) {
        pressedInside = true
    }

    override func mouseDragged(with event: NSEvent) {
        // A press that moves without leaving the shape does not cancel the click; only leaving it does.
        let point = convert(event.locationInWindow, from: nil)
        pressedInside = shapeLayer.path?.contains(point) ?? false
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = pressedInside
        pressedInside = false
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

        func origin(for size: CGSize) -> CGPoint {
            CGPoint(x: (envelopeSize.width - size.width) / 2, y: envelopeSize.height - size.height)
        }
        // 0 = flush card shape, 1 = full pill — interpolated continuously, not switched at a threshold.
        let startPillness: Double = startGap != nil ? 1 : 0
        let targetPillness: Double = targetGap != nil ? 1 : 0
        func insetAndRadius(for size: CGSize, at t: Double) -> (inset: CGFloat, radius: CGFloat) {
            let pillness = CGFloat(startPillness + (targetPillness - startPillness) * t)
            let inset = (startGap ?? 0) + ((targetGap ?? 0) - (startGap ?? 0)) * CGFloat(t)
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
        func outlinePath(for size: CGSize, at t: Double) -> CGPath {
            let (inset, radius) = insetAndRadius(for: size, at: t)
            return translated(edgePath(size: size, inset: inset, cornerRadius: radius), for: size)
        }

        if reduceMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.path = fillPath(for: target, at: 1)
            edgeLayer.path = outlinePath(for: target, at: 1)
            CATransaction.commit()
            completion()
            return
        }

        let (sizes, keyTimes, duration) = IslandMotion.frames(from: start, to: target)
        let fillPaths = zip(sizes, keyTimes).map { fillPath(for: $0, at: $1) }
        let outlinePaths = zip(sizes, keyTimes).map { outlinePath(for: $0, at: $1) }

        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = fillPaths
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = duration
        animation.setValue(generation, forKey: "islandGeneration")

        let edgeAnimation = CAKeyframeAnimation(keyPath: "path")
        edgeAnimation.values = outlinePaths
        edgeAnimation.keyTimes = animation.keyTimes
        edgeAnimation.calculationMode = .linear
        edgeAnimation.duration = duration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = fillPaths.last
        shapeLayer.add(animation, forKey: Self.motionKey)
        edgeLayer.path = outlinePaths.last
        edgeLayer.add(edgeAnimation, forKey: Self.motionKey)
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, generation == self.animationGeneration else { return }
            self.shapeLayer.removeAnimation(forKey: Self.motionKey)
            self.edgeLayer.removeAnimation(forKey: Self.motionKey)
            completion()
        }
    }
}
