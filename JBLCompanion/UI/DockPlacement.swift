import CoreGraphics

/// Which screen edge the island is docked to — design/DESIGN_GUIDE.md §6. Pure, Codable (for
/// UserDefaults persistence), framework-free.
enum DockEdge: String, CaseIterable, Codable, Equatable {
    case top, bottom, left, right

    var isVertical: Bool { self == .left || self == .right }
}

/// Placement math for the three edges IslandGeometry doesn't already handle (bottom/left/right —
/// `.top` keeps using IslandGeometry's own notch/capsule-aware sizing and frame, since notch
/// fusion has no equivalent on the other three edges; NotchPanel calls into this only for the
/// other three, plus the shared offset-clamping/drag-threshold/ordering helpers below, which apply
/// uniformly to all four). Every function takes screen/visible frames as plain CGRects — no
/// NSScreen dependency, so this is fully unit-testable without a real display.
enum DockPlacement {
    /// The default distance from the edge the pill/card dock to (§6 originally specified "10 from
    /// the edge" for left/right, "12" for bottom) — user-adjustable now
    /// (IslandSettings.edgeMargin(for:)), same margin for every edge including top
    /// (IslandGeometry's own `topMargin`). §6's own smaller numbers turned out not to be just a
    /// cosmetic choice: on hover, CollapsedPill scales up (MotionConstants.pillHoverScale, 1.06)
    /// and its shadow/glow can bleed up to ~13pt (the notch glow's own blur radius) — at the
    /// guide's original 10/12, that growth, right on the docked edge where there's zero window
    /// envelope margin by design (restingEnvelopeSize's own doc comment), clipped flat against the
    /// window's own hard edge on hover. 20 clears that with real room to spare at every pill size.
    static func edgeMargin(for edge: DockEdge) -> CGFloat {
        _ = edge
        return 20
    }

    /// A floor that clears hover-scale + shadow bleed at the largest pill size (see `edgeMargin`'s
    /// own doc comment for the arithmetic) on every edge, not just a tight range around the
    /// default — a user-chosen margin below this would reintroduce that same hover clipping.
    static let edgeMarginRange: ClosedRange<CGFloat> = 20...80

    /// CollapsedPill's own default diameter — a circle, the same size on every edge, deliberately
    /// deviating from design/DESIGN_GUIDE.md §3's own elongated 46x34/34x46 pill (CLAUDE.md
    /// records this one too). Being edge-independent isn't just cosmetic: the old size *and*
    /// shape both depended on `edge.isVertical`, and CollapsedPill's own content layout (an HStack
    /// for horizontal docks, a VStack for vertical ones) depended on it too — switching edges
    /// without something to force a re-render left the old layout's background visibly showing
    /// through the new one for a moment. A circle has no long axis, so there's nothing left for
    /// edge to change here at all. User-adjustable now (IslandSettings.pillDiameter) — this is
    /// just the fallback for an unset default.
    static let collapsedPillDiameter: CGFloat = 52
    static let pillDiameterRange: ClosedRange<CGFloat> = 40...100

    /// CollapsedPill's own size — mirrored here, not read from CollapsedPill itself, since that's
    /// a SwiftUI view and this module stays framework-free. Keeps the `for edge:` signature
    /// callers already use even though a circle no longer actually varies by edge.
    static func collapsedPillSize(for edge: DockEdge, diameter: CGFloat) -> CGSize {
        _ = edge
        return CGSize(width: diameter, height: diameter)
    }

    /// How far the native silhouette's drawn circle insets from the collapsed pill's own frame on
    /// bottom/left/right — small enough that CollapsedPill's own full-size SwiftUI circle (no
    /// inset of its own) fully covers it, matching IslandGeometry.floatingGap's own default for
    /// the top edge (there, it floats a notched display's safe-area camera-height detection; here
    /// there's no such thing to measure, so this is just that same small default, flat).
    static let collapsedPillInset: CGFloat = 4

    /// The frame for `size` docked to `edge`, offset by `offset` points from the middle of the
    /// edge (positive = right for top/bottom, down for left/right), using `visibleFrame` so a
    /// bottom dock naturally sits above the Dock. Centered (offset 0) by default — §6: "centred
    /// along its edge unless dragged." Callers are expected to have already clamped `offset` via
    /// `clampedOffset` below; this function does no clamping itself, so a geometry test can see
    /// an out-of-range offset's raw effect if it wants to.
    static func frame(for size: CGSize, edge: DockEdge, offset: CGFloat, visibleFrame: CGRect, margin: CGFloat) -> CGRect {
        switch edge {
        case .top:
            // IslandGeometry.frame(for:) handles .top's own y (notch fusion / menu-bar drop);
            // this branch exists only so `frame(for:edge:...)` is total, for a caller that wants
            // a uniform entry point — NotchPanel never actually calls it for .top.
            return CGRect(x: visibleFrame.midX + offset - size.width / 2, y: visibleFrame.maxY - margin - size.height, width: size.width, height: size.height)
        case .bottom:
            return CGRect(x: visibleFrame.midX + offset - size.width / 2, y: visibleFrame.minY + margin, width: size.width, height: size.height)
        case .left:
            return CGRect(x: visibleFrame.minX + margin, y: visibleFrame.midY + offset - size.height / 2, width: size.width, height: size.height)
        case .right:
            return CGRect(x: visibleFrame.maxX - margin - size.width, y: visibleFrame.midY + offset - size.height / 2, width: size.width, height: size.height)
        }
    }

    /// The offset range (from the edge's own middle) that keeps `size`, docked to `edge`, at
    /// least `margin` inside `visibleFrame` on both ends. `nil` means `size` doesn't fit inside
    /// `visibleFrame` at all at any offset (a degenerate/tiny-screen case) — callers fall back to
    /// offset 0 (centered) rather than pick a meaningless range.
    static func offsetRange(forSize size: CGSize, edge: DockEdge, visibleFrame: CGRect, margin: CGFloat) -> ClosedRange<CGFloat>? {
        switch edge {
        case .top, .bottom:
            let half = size.width / 2
            let low = visibleFrame.minX + margin + half - visibleFrame.midX
            let high = visibleFrame.maxX - margin - half - visibleFrame.midX
            guard low <= high else { return nil }
            return low...high
        case .left, .right:
            let half = size.height / 2
            let low = visibleFrame.minY + margin + half - visibleFrame.midY
            let high = visibleFrame.maxY - margin - half - visibleFrame.midY
            guard low <= high else { return nil }
            return low...high
        }
    }

    /// Clamps a drag offset so *both* the collapsed pill and the expanded card stay 8pt inside
    /// `visibleFrame` at that same offset — the task's own "clamped... in both the collapsed and
    /// expanded states." Falls back to 0 (centered) if the two sizes' valid ranges don't overlap
    /// at all (the expanded card doesn't fit anywhere, degenerate screen) or neither fits.
    static func clampedOffset(
        _ offset: CGFloat, collapsedSize: CGSize, expandedSize: CGSize, edge: DockEdge,
        visibleFrame: CGRect, margin: CGFloat = 8
    ) -> CGFloat {
        guard let collapsedRange = offsetRange(forSize: collapsedSize, edge: edge, visibleFrame: visibleFrame, margin: margin),
              let expandedRange = offsetRange(forSize: expandedSize, edge: edge, visibleFrame: visibleFrame, margin: margin)
        else { return 0 }
        let low = max(collapsedRange.lowerBound, expandedRange.lowerBound)
        let high = min(collapsedRange.upperBound, expandedRange.upperBound)
        guard low <= high else { return 0 }
        return min(max(offset, low), high)
    }

    /// §4's own point: "A click that moves less than a few points is a click, not a drag."
    static let dragThreshold: CGFloat = 4

    static func isDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) > dragThreshold
    }

    enum EdgeChangeStep: Equatable {
        /// The card is already expanded — collapse it first, then move the pill, then expand
        /// from the new edge (§6: "Changing the edge while the card is expanded: collapse first,
        /// move the pill, then expand from the new edge. Never animate the card across the
        /// screen").
        case collapseFirst
        /// Nothing is expanded — the pill can just move directly to the new edge.
        case moveDirectly
    }

    static func edgeChangeOrdering(isExpanded: Bool) -> EdgeChangeStep {
        isExpanded ? .collapseFirst : .moveDirectly
    }
}
