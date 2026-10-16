import CoreGraphics

/// Builds the island's silhouette path. The exact source (`NotchShape`) wasn't one of the three
/// files the brief named to read, so this is my own reading of its description: flat top (flush
/// with the screen edge, nothing visible above it), small concave "shoulders" easing the top
/// corners into the vertical sides, and a flat bottom edge between two ordinary rounded bottom
/// corners — a capsule variant replaces all of that with a plain rounded pill, inset by the
/// floating gap on every side. Treat the visual shape as approximate; the geometry/motion/sizing
/// math around it is what's load-bearing.
enum IslandShape {
    static let shoulderRadius: CGFloat = 14

    /// `size` in a bottom-left-origin, y-up local coordinate space (CGPath's own convention) —
    /// y=0 is the shape's bottom (what hangs into the desktop), y=size.height is its top (flush
    /// with the screen edge for the notch style).
    static func path(size: CGSize, floatingGap: CGFloat?) -> CGPath {
        let width = max(size.width, 0.01)
        let height = max(size.height, 0.01)
        if let gap = floatingGap {
            return capsulePath(width: width, height: height, gap: gap)
        }
        return notchPath(width: width, height: height)
    }

    private static func capsulePath(width: CGFloat, height: CGFloat, gap: CGFloat) -> CGPath {
        let rect = CGRect(x: gap, y: gap, width: max(0, width - gap * 2), height: max(0, height - gap * 2))
        let radius = max(0, min(rect.width, rect.height) / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    private static func notchPath(width: CGFloat, height: CGFloat) -> CGPath {
        let bottomRadius = min(28, height * 0.34, width / 2)
        let shoulder = min(shoulderRadius, width / 2 - bottomRadius, height - bottomRadius)
            .clamped(to: 0...shoulderRadius)

        let path = CGMutablePath()
        // Top-left shoulder: a small concave ease from the top edge into the left side.
        path.move(to: CGPoint(x: shoulder, y: height))
        path.addQuadCurve(to: CGPoint(x: 0, y: height - shoulder), control: CGPoint(x: 0, y: height))
        // Down the left side to the bottom-left rounded corner.
        path.addLine(to: CGPoint(x: 0, y: bottomRadius))
        path.addQuadCurve(to: CGPoint(x: bottomRadius, y: 0), control: CGPoint(x: 0, y: 0))
        // Flat bottom edge.
        path.addLine(to: CGPoint(x: width - bottomRadius, y: 0))
        // Bottom-right rounded corner, up the right side.
        path.addQuadCurve(to: CGPoint(x: width, y: bottomRadius), control: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: height - shoulder))
        // Top-right shoulder.
        path.addQuadCurve(to: CGPoint(x: width - shoulder, y: height), control: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: shoulder, y: height))
        path.closeSubpath()
        return path
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        guard range.lowerBound <= range.upperBound else { return range.lowerBound }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
