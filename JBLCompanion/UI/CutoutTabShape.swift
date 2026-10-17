import SwiftUI

/// The expanded card's cut-out tab — design/DESIGN_GUIDE.md §4 "The cut-out tab": a piece of the
/// frame that pushes into the panel, concave-filleted where it meets the panel edge so it reads as
/// one cut piece rather than a stuck-on badge.
///
/// Built once, in "top dock" local space (tab hangs down from a horizontal edge, centered at
/// x=0, the edge itself at y=0), then placed for the other three docks with an affine transform —
/// bottom/left/right aren't just rotations of the same rectangle (top/bottom use a 116x32 body,
/// left/right a 30x92 one), so `lengthAlongEdge`/`depthIntoPanel` are passed in already correct
/// for the dock, and only the placement transform varies.
struct CutoutTabShape: Shape {
    let dock: CardDock
    let lengthAlongEdge: CGFloat
    let depthIntoPanel: CGFloat
    var outerCornerRadius: CGFloat = 18
    var filletRadius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        Self.canonicalTopPath(
            lengthAlongEdge: lengthAlongEdge, depthIntoPanel: depthIntoPanel,
            outerCornerRadius: outerCornerRadius, filletRadius: filletRadius
        )
        .applying(placementTransform(in: rect))
    }

    private func placementTransform(in rect: CGRect) -> CGAffineTransform {
        switch dock {
        case .top:
            return CGAffineTransform(translationX: rect.midX, y: rect.minY)
        case .bottom:
            // Flip vertically (tab points up into the panel) and anchor to the bottom edge.
            return CGAffineTransform(scaleX: 1, y: -1)
                .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.maxY))
        case .left:
            // Rotate so "along edge" runs vertically and "depth" runs rightward from the left edge.
            return CGAffineTransform(rotationAngle: .pi / 2)
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.midY))
        case .right:
            return CGAffineTransform(rotationAngle: -.pi / 2)
                .concatenating(CGAffineTransform(scaleX: -1, y: 1))
                .concatenating(CGAffineTransform(translationX: rect.maxX, y: rect.midY))
        }
    }

    /// `half` = half of `lengthAlongEdge`. `r1` = filletRadius, `r2` = outerCornerRadius.
    /// See this file's own header comment for the coordinate space.
    private static func canonicalTopPath(lengthAlongEdge: CGFloat, depthIntoPanel: CGFloat, outerCornerRadius r2: CGFloat, filletRadius r1: CGFloat) -> Path {
        let half = lengthAlongEdge / 2
        var path = Path()

        // Far-left edge point -> far-right edge point, along the panel's own edge.
        path.move(to: CGPoint(x: -half - r1, y: 0))
        path.addLine(to: CGPoint(x: half + r1, y: 0))

        // Right fillet (concave): centre sits r1 below this outer-end point, so the arc flares
        // outward at the edge and tapers in to the wall — §4's "curve down and in." SwiftUI's
        // Path.addArc clockwise flag sweeps the *short* way when true for this geometry (verified
        // empirically via the snapshot harness — the naive false/true assignment below produced
        // the 270° "wrong way round" sweep instead, rendering as a cluster of near-full circles).
        path.addArc(center: CGPoint(x: half + r1, y: r1), radius: r1, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: true)

        // Down the right wall to where the bottom-right corner starts.
        path.addLine(to: CGPoint(x: half, y: r1 + depthIntoPanel - r2))
        // Bottom-right corner (ordinary convex rounding).
        path.addArc(center: CGPoint(x: half - r2, y: r1 + depthIntoPanel - r2), radius: r2, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        // Along the bottom.
        path.addLine(to: CGPoint(x: -half + r2, y: r1 + depthIntoPanel))
        // Bottom-left corner (convex).
        path.addArc(center: CGPoint(x: -half + r2, y: r1 + depthIntoPanel - r2), radius: r2, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

        // Up the left wall.
        path.addLine(to: CGPoint(x: -half, y: r1))
        // Left fillet (concave, mirrored), back to the start.
        path.addArc(center: CGPoint(x: -half - r1, y: r1), radius: r1, startAngle: .degrees(0), endAngle: .degrees(-90), clockwise: true)

        path.closeSubpath()
        return path
    }
}
