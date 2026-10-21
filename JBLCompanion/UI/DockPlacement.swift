import CoreGraphics

/// Which screen edge the island is docked to — design/DESIGN_GUIDE.md §6. Pure, Codable (for
/// UserDefaults persistence), framework-free.
enum DockEdge: String, CaseIterable, Codable, Equatable {
    case top, bottom, left, right

    var isVertical: Bool { self == .left || self == .right }
}

/// A corner dock — distinct from docking to a single `DockEdge`. Owner request: dragging the
/// island near where two edges meet should fuse it into that exact corner (a quarter-disc shape,
/// flush against both edges at once, logo-mark-only content) instead of either overflowing past
/// the adjacent edge (what a plain `.top`/`.bottom` dock did near a corner before this existed) or
/// sitting as a free-floating circle near, but not flush with, the corner. Pure, Codable (for
/// UserDefaults persistence), framework-free — same reasoning as `DockEdge`.
enum ScreenCorner: String, CaseIterable, Codable, Equatable {
    case topLeft, topRight, bottomLeft, bottomRight
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

    /// Floor removed at the owner's explicit request (flush-to-the-edge docking matters more than
    /// the hover-scale/shadow-bleed clipping a 20pt floor used to guarantee clearing — see
    /// `edgeMargin`'s own doc comment for that arithmetic). A margin near 0 can again clip
    /// CollapsedPill's hover-scale growth and shadow/glow bleed flat against the window's own hard
    /// edge on hover; that's now an accepted tradeoff, not an oversight.
    static let edgeMarginRange: ClosedRange<CGFloat> = 0...80

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

    // MARK: - Corner docking

    /// The exact screen-corner coordinate `corner` refers to, in `visibleFrame`.
    static func cornerPoint(_ corner: ScreenCorner, visibleFrame: CGRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: visibleFrame.minX, y: visibleFrame.maxY)
        case .topRight: return CGPoint(x: visibleFrame.maxX, y: visibleFrame.maxY)
        case .bottomLeft: return CGPoint(x: visibleFrame.minX, y: visibleFrame.minY)
        case .bottomRight: return CGPoint(x: visibleFrame.maxX, y: visibleFrame.minY)
        }
    }

    /// Whichever corner `contentFrame` (the dropped pill's own *visible content* rect — never the
    /// padded shadow-margin envelope, same reasoning `NotchPanel.handleDragEnd()`'s own doc
    /// comment gives for why its single-edge distances are measured this way too) is closest to,
    /// as long as its own matching corner is within `snapDistance` of `visibleFrame`'s — `nil`
    /// when nothing is close enough, so the caller falls back to its existing single-edge docking
    /// logic.
    ///
    /// Measured corner-to-corner (`contentFrame`'s own top-left vs. `visibleFrame`'s, etc.), never
    /// center-to-corner: the window's own live drag boundary clamp keeps `contentFrame` fully on
    /// screen at all times, which already puts its *center* a full `radius` away from any literal
    /// screen corner even when it's dropped as close to one as physically possible — a
    /// center-to-corner check could never be satisfied by any on-screen drop at all, silently
    /// never triggering regardless of `snapDistance`. Corner-to-corner reaches exactly 0 the
    /// moment the content is flush in the corner, same as the single-edge check already does for
    /// one edge at a time.
    static func nearestCorner(contentFrame: CGRect, visibleFrame: CGRect, snapDistance: CGFloat) -> ScreenCorner? {
        func contentCornerPoint(_ corner: ScreenCorner) -> CGPoint {
            switch corner {
            case .topLeft: return CGPoint(x: contentFrame.minX, y: contentFrame.maxY)
            case .topRight: return CGPoint(x: contentFrame.maxX, y: contentFrame.maxY)
            case .bottomLeft: return CGPoint(x: contentFrame.minX, y: contentFrame.minY)
            case .bottomRight: return CGPoint(x: contentFrame.maxX, y: contentFrame.minY)
            }
        }
        return ScreenCorner.allCases
            .map { corner -> (ScreenCorner, CGFloat) in
                let a = contentCornerPoint(corner)
                let b = cornerPoint(corner, visibleFrame: visibleFrame)
                return (corner, hypot(a.x - b.x, a.y - b.y))
            }
            .filter { $0.1 <= snapDistance }
            .min { $0.1 < $1.1 }
            .map(\.0)
    }

    /// The frame for `size` (a square bounding box) docked flush into `corner`, inset by `margin`
    /// from both edges that meet there. Unlike `frame(for:edge:offset:...)`, there's no free axis
    /// to offset along — a corner dock is fully determined by `corner` alone, which is exactly
    /// what keeps the same physical point anchored between the collapsed quarter-disc and the
    /// expanded card: both this function's `size` parameter and its *result* change together, but
    /// the corner they're flush against never moves, so there's nothing left to visibly displace
    /// when expanding/collapsing from a corner (NotchPanel.windowFrame(for:)'s own doc comment).
    static func cornerFrame(for size: CGSize, corner: ScreenCorner, visibleFrame: CGRect, margin: CGFloat) -> CGRect {
        let x: CGFloat
        switch corner {
        case .topLeft, .bottomLeft: x = visibleFrame.minX + margin
        case .topRight, .bottomRight: x = visibleFrame.maxX - margin - size.width
        }
        let y: CGFloat
        switch corner {
        case .topLeft, .topRight: y = visibleFrame.maxY - margin - size.height
        case .bottomLeft, .bottomRight: y = visibleFrame.minY + margin
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// A quarter-disc silhouette, flush into `corner` of its own `size`-sized local bounds — the
    /// collapsed corner-dock shape (a "1/4 ball"), built directly as an arc rather than reusing
    /// `IslandShape`'s rounded-rect family (a quarter-disc isn't a rounded rect at any corner
    /// radius). `size` is assumed square; `min(size.width, size.height)` is used as the radius if
    /// it isn't. Local coordinates, AppKit convention (origin bottom-left, y increasing upward) —
    /// matches `NotchSilhouetteView`, which never overrides `isFlipped`.
    ///
    /// Geometrically: the circle's own center sits exactly at the flush corner (`corner`'s own
    /// local point), the two straight edges run along the two sides of `size` that meet there, and
    /// the curved edge is the arc between their far ends, sweeping the one quadrant that's inside
    /// `size`'s own bounds. `clockwise: false` sweeps `startAngle` toward `endAngle` by increasing
    /// raw angle (the standard, flip-independent meaning of CGPath's own `clockwise` parameter) —
    /// if this ever renders as a concave sliver instead of a convex quarter-disc, that's the one
    /// value to flip; nothing else here needs to change.
    static func quarterCirclePath(size: CGSize, corner: ScreenCorner) -> CGPath {
        let radius = min(size.width, size.height)
        let flushCorner: CGPoint
        let startAngle: CGFloat
        switch corner {
        case .bottomLeft: flushCorner = CGPoint(x: 0, y: 0); startAngle = 0
        case .bottomRight: flushCorner = CGPoint(x: size.width, y: 0); startAngle = .pi / 2
        case .topRight: flushCorner = CGPoint(x: size.width, y: size.height); startAngle = .pi
        case .topLeft: flushCorner = CGPoint(x: 0, y: size.height); startAngle = -.pi / 2
        }
        let endAngle = startAngle + .pi / 2
        let path = CGMutablePath()
        let arcStart = CGPoint(x: flushCorner.x + radius * cos(startAngle), y: flushCorner.y + radius * sin(startAngle))
        path.move(to: flushCorner)
        path.addLine(to: arcStart)
        path.addArc(center: flushCorner, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Free-floating tray direction (owner spec, 2026-10-21)

/// A 3x3 division of the visible screen, used only while the island is free-floating (not docked
/// to an edge or a corner — `DockPlacement.trayDirection(for:)`'s own doc comment covers why
/// edge/corner docks never consult this at all). Numbered 1-9 the same way the owner's own spec
/// does: 1-3 top row (left to right), 4-6 middle row, 7-9 bottom row.
enum GridRegion: Int, CaseIterable, Equatable {
    case topLeft = 1, topCenter = 2, topRight = 3
    case middleLeft = 4, center = 5, middleRight = 6
    case bottomLeft = 7, bottomCenter = 8, bottomRight = 9
}

/// Which side of the island the tray extends toward. The notch always sits on the tray's own
/// *opposite* edge (`DockPlacement.notchDirection(for:)`) — the one facing back at the island,
/// since that's the edge the tray is visually "unfolding from."
enum TrayDirection: String, Equatable {
    case up, down, left, right
}

extension DockPlacement {
    /// Which of the 3x3 regions `center` falls into, within `visibleFrame`. A center exactly on a
    /// grid line is deliberately *not* a tie needing special-casing at the call site — column
    /// ties resolve to the right-hand region, row ties resolve to the lower (bottom-ward) region,
    /// both by construction below (owner's own spec: "a center exactly on a grid line belongs to
    /// one consistent region — e.g. the lower/right one").
    ///
    /// Column uses a strict `<` test per bucket, checked left to right — a value exactly on a
    /// boundary fails the left bucket's test and falls through to the right one. Row uses `<=`
    /// per bucket, checked bottom to top (`rowT` is 0 at the screen's bottom, 1 at its top, AppKit
    /// convention — the same `visibleFrame`/y-up convention every other function in this file
    /// already uses) — a value exactly on a boundary passes the lower bucket's test first and
    /// stays there, rather than falling through to the upper one.
    static func gridRegion(for center: CGPoint, visibleFrame: CGRect) -> GridRegion {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return .center }
        let colT = (center.x - visibleFrame.minX) / visibleFrame.width
        let rowT = (center.y - visibleFrame.minY) / visibleFrame.height
        let col: Int = colT < 1.0 / 3.0 ? 0 : (colT < 2.0 / 3.0 ? 1 : 2)
        let row: Int = rowT <= 1.0 / 3.0 ? 0 : (rowT <= 2.0 / 3.0 ? 1 : 2)
        switch (row, col) {
        case (2, 0): return .topLeft
        case (2, 1): return .topCenter
        case (2, 2): return .topRight
        case (1, 0): return .middleLeft
        case (1, 1): return .center
        case (1, 2): return .middleRight
        case (0, 0): return .bottomLeft
        case (0, 1): return .bottomCenter
        default: return .bottomRight
        }
    }

    /// The owner's own table, verbatim: top row and the dead center open downward; middle-left
    /// opens rightward; middle-right opens leftward; bottom row opens upward. Every case points
    /// the tray away from the nearest screen edge and back toward the screen's own open middle,
    /// which is what keeps it from immediately needing to clamp back on-screen in the common case.
    static func trayDirection(for region: GridRegion) -> TrayDirection {
        switch region {
        case .topLeft, .topCenter, .topRight: return .down
        case .middleLeft: return .right
        case .center: return .down
        case .middleRight: return .left
        case .bottomLeft, .bottomCenter, .bottomRight: return .up
        }
    }

    /// The tray's own notch always sits on the edge facing back at the island — simply the
    /// opposite side from whichever direction the tray extends.
    static func notchDirection(for trayDirection: TrayDirection) -> TrayDirection {
        switch trayDirection {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    /// The tray's unclamped origin: adjacent to the island (never overlapping it — `gap` of real
    /// space between them), on whichever side `direction` names, centered on the island's own
    /// center along the perpendicular axis. `islandSize`/`traySize` are both plain content sizes
    /// (not window envelopes — NotchPanel's own doc comments on `restingEnvelopeSize`/
    /// `cornerEnvelopeSize` cover why those stay a separate, later concern from this pure
    /// placement math).
    static func trayOrigin(islandCenter: CGPoint, islandSize: CGSize, traySize: CGSize, direction: TrayDirection, gap: CGFloat) -> CGPoint {
        switch direction {
        case .down:
            return CGPoint(x: islandCenter.x - traySize.width / 2, y: islandCenter.y - islandSize.height / 2 - gap - traySize.height)
        case .up:
            return CGPoint(x: islandCenter.x - traySize.width / 2, y: islandCenter.y + islandSize.height / 2 + gap)
        case .right:
            return CGPoint(x: islandCenter.x + islandSize.width / 2 + gap, y: islandCenter.y - traySize.height / 2)
        case .left:
            return CGPoint(x: islandCenter.x - islandSize.width / 2 - gap - traySize.width, y: islandCenter.y - traySize.height / 2)
        }
    }

    /// Clamps `origin` to keep the tray fully inside `visibleFrame` — only along the axis
    /// *perpendicular* to `direction`. The axis `direction` itself controls (which side of the
    /// island the tray is on) is deliberately never touched here: clamping that axis instead could
    /// slide the tray back over the island it's supposed to stay clear of, exactly the overlap
    /// `trayOrigin(...)` was built to avoid in the first place.
    static func clampedTrayOrigin(_ origin: CGPoint, traySize: CGSize, visibleFrame: CGRect, direction: TrayDirection) -> CGPoint {
        switch direction {
        case .up, .down:
            let x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - traySize.width)
            return CGPoint(x: x, y: origin.y)
        case .left, .right:
            let y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - traySize.height)
            return CGPoint(x: origin.x, y: y)
        }
    }

    /// Where the notch sits along the tray's own facing edge (`notchDirection(for:)`), as an
    /// offset from that edge's own midpoint — same offset convention `frame(for:edge:offset:...)`
    /// already uses elsewhere in this file. Tracks the island's actual position along that edge as
    /// closely as possible, but clamped to stay `cornerRadius + notchHalfLength` away from either
    /// end — the owner's own addition: "constrain it to the tray's straight edge... so it never
    /// overhangs" a rounded corner, same reasoning `ExpandedCard.cornerTabPosition`'s own
    /// `alongEdgeInset` already applies to the corner-docked tab.
    static func notchOffset(
        islandCenter: CGPoint, trayOrigin: CGPoint, traySize: CGSize, direction: TrayDirection,
        cornerRadius: CGFloat, notchHalfLength: CGFloat
    ) -> CGFloat {
        switch direction {
        case .up, .down:
            let desired = islandCenter.x - (trayOrigin.x + traySize.width / 2)
            let maxOffset = max(0, traySize.width / 2 - cornerRadius - notchHalfLength)
            return min(max(desired, -maxOffset), maxOffset)
        case .left, .right:
            let desired = islandCenter.y - (trayOrigin.y + traySize.height / 2)
            let maxOffset = max(0, traySize.height / 2 - cornerRadius - notchHalfLength)
            return min(max(desired, -maxOffset), maxOffset)
        }
    }

    /// Whether `traySize`, placed at `origin`, fits entirely inside `visibleFrame` with no
    /// clamping needed at all (on *either* axis — unlike `clampedTrayOrigin`, which only ever
    /// touches the perpendicular one).
    static func trayFits(origin: CGPoint, traySize: CGSize, visibleFrame: CGRect) -> Bool {
        origin.x >= visibleFrame.minX && origin.x + traySize.width <= visibleFrame.maxX
            && origin.y >= visibleFrame.minY && origin.y + traySize.height <= visibleFrame.maxY
    }

    /// The full placement decision, in the owner's own priority order: try `preferredDirection`
    /// first: and if the tray genuinely fits there with no clamping at all, use it exactly as is.
    /// If not, try the *opposite* direction instead (e.g. `.down` became `.up`) — same reasoning
    /// `trayDirection(for:)`'s own table already leans on: flipping to the open side of the
    /// island, rather than clamping a tray that doesn't actually fit where it was asked to go, is
    /// what keeps the tray from being squashed up against a screen edge it didn't need to be
    /// anywhere near. Only once *neither* direction fits at all does this fall back to clamping
    /// the originally preferred one (`clampedTrayOrigin`'s own doc comment covers why that only
    /// ever touches the perpendicular axis, never the one keeping the tray off the island).
    static func trayPlacement(
        islandCenter: CGPoint, islandSize: CGSize, traySize: CGSize, preferredDirection: TrayDirection,
        gap: CGFloat, visibleFrame: CGRect
    ) -> (origin: CGPoint, direction: TrayDirection) {
        let preferredOrigin = trayOrigin(islandCenter: islandCenter, islandSize: islandSize, traySize: traySize, direction: preferredDirection, gap: gap)
        if trayFits(origin: preferredOrigin, traySize: traySize, visibleFrame: visibleFrame) {
            return (preferredOrigin, preferredDirection)
        }
        let oppositeDirection = notchDirection(for: preferredDirection) // same up<->down/left<->right mapping
        let oppositeOrigin = trayOrigin(islandCenter: islandCenter, islandSize: islandSize, traySize: traySize, direction: oppositeDirection, gap: gap)
        if trayFits(origin: oppositeOrigin, traySize: traySize, visibleFrame: visibleFrame) {
            return (oppositeOrigin, oppositeDirection)
        }
        return (clampedTrayOrigin(preferredOrigin, traySize: traySize, visibleFrame: visibleFrame, direction: preferredDirection), preferredDirection)
    }
}
