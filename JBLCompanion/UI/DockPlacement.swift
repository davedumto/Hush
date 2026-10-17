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
    /// §6 "10 from the edge" (left/right) / "12 above the bottom, or above the Dock" (bottom) —
    /// the same margin the pill and the card both anchor to on these three edges (the card simply
    /// being much bigger is what makes it "grow away from the edge").
    static func edgeMargin(for edge: DockEdge) -> CGFloat {
        edge == .bottom ? 12 : 10
    }

    /// CollapsedPill's own fixed size (design/DESIGN_GUIDE.md §3) — mirrored here, not read from
    /// CollapsedPill itself, since that's a SwiftUI view and this module stays framework-free.
    static func collapsedPillSize(for edge: DockEdge) -> CGSize {
        edge.isVertical ? CGSize(width: 34, height: 46) : CGSize(width: 46, height: 34)
    }

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
