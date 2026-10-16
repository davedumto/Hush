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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        shapeLayer.fillColor = NSColor.black.cgColor
        layer?.addSublayer(shapeLayer)
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
    /// the wide expanded card. The gap is linearly interpolated between them across the resize,
    /// so a capsule's rounded ends visually ease open as it grows into the card (and back as it
    /// shrinks). Calls `completion` once the resize has settled (or immediately, unanimated,
    /// under Reduce Motion).
    func resize(
        to target: CGSize, from start: CGSize, startGap: CGFloat?, targetGap: CGFloat?,
        envelopeSize: CGSize, reduceMotion: Bool, completion: @escaping () -> Void
    ) {
        animationGeneration += 1
        let generation = animationGeneration

        frame = CGRect(origin: .zero, size: envelopeSize)
        shapeLayer.frame = CGRect(origin: .zero, size: envelopeSize)

        func origin(for size: CGSize) -> CGPoint {
            CGPoint(x: (envelopeSize.width - size.width) / 2, y: envelopeSize.height - size.height)
        }
        func gap(at t: Double) -> CGFloat? {
            let s = startGap ?? 0
            let e = targetGap ?? 0
            guard s != 0 || e != 0 else { return nil }
            let interpolated = s + (e - s) * CGFloat(t)
            return interpolated > 0.5 ? interpolated : nil
        }
        func path(for size: CGSize, at t: Double) -> CGPath {
            let raw = IslandShape.path(size: size, floatingGap: gap(at: t))
            var transform = CGAffineTransform(translationX: origin(for: size).x, y: origin(for: size).y)
            return raw.copy(using: &transform) ?? raw
        }

        if reduceMotion {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeLayer.path = path(for: target, at: 1)
            CATransaction.commit()
            completion()
            return
        }

        let (sizes, keyTimes, duration) = IslandMotion.frames(from: start, to: target)
        let paths = zip(sizes, keyTimes).map { path(for: $0, at: $1) }

        let animation = CAKeyframeAnimation(keyPath: "path")
        animation.values = paths
        animation.keyTimes = keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = duration
        animation.setValue(generation, forKey: "islandGeneration")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeLayer.path = paths.last
        shapeLayer.add(animation, forKey: Self.motionKey)
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, generation == self.animationGeneration else { return }
            self.shapeLayer.removeAnimation(forKey: Self.motionKey)
            completion()
        }
    }
}
