import CoreGraphics
import Foundation

/// Per-display menu-bar height cache, ported near-verbatim from NotchMenuBarMeasurements. Needed
/// because an auto-hidden menu bar makes `visibleFrame` momentarily lie about the real bar height —
/// the last known-good reading is kept per display until the bar shows again.
struct MenuBarMeasurements {
    private struct Reading: Equatable { let size: CGSize; let scale: CGFloat; let height: CGFloat }
    private static let range: ClosedRange<CGFloat> = 16...64
    private var readings: [UInt32: Reading] = [:]

    static func showsBar(frame: CGRect, visibleTop: CGFloat) -> Bool {
        let gap = frame.maxY - visibleTop
        return gap.isFinite && range.contains(gap)
    }

    mutating func retainDisplays(_ ids: [UInt32]) {
        readings = readings.filter { ids.contains($0.key) }
    }

    mutating func height(
        displayID: UInt32, frame: CGRect, visibleTop: CGFloat, scale: CGFloat, statusBarThickness: CGFloat
    ) -> CGFloat {
        let range = Self.range
        let gap = frame.maxY - visibleTop
        let canRemember = displayID != 0 && scale.isFinite && scale > 0
        if let previous = readings[displayID], previous.size != frame.size || previous.scale != scale {
            readings[displayID] = nil
        }
        if Self.showsBar(frame: frame, visibleTop: visibleTop) {
            if canRemember { readings[displayID] = Reading(size: frame.size, scale: scale, height: gap) }
            return gap
        }
        if canRemember, let previous = readings[displayID] { return previous.height }
        return statusBarThickness.isFinite && range.contains(statusBarThickness) ? statusBarThickness : 24
    }
}

/// The island's shape and placement on one display — a deliberately small subset of
/// vorssaint-utils's NotchGeometry (no header rows, pages, music strips, quick access; this app
/// has none of that). Pure — screen is passed in as a plain CGRect, no NSScreen dependency.
struct IslandGeometry: Equatable {
    let screen: CGRect
    let cameraWidth: CGFloat
    let cameraHeight: CGFloat
    let isNotched: Bool
    let menuBarHeight: CGFloat
    /// Nil hangs the island flush from the top edge (a real camera's own housing). Every other
    /// case — no physical camera, on any edge — is always a plain floating circle instead, sized
    /// and shaped by NotchPanel.collapsedSize(for:geometry:)/DockPlacement, not by this geometry
    /// at all; `floatingGap`/`floatingDrop` here only still matter for a real notch's own frame.
    let floatingGap: CGFloat?
    /// A few points, never 0 — keeps the window's own top edge from landing exactly on the
    /// screen's physical top edge. Flush against it clipped the collapsed pill's rounded top
    /// corner outright (no sub-pixel room for the circle's own antialiasing to resolve into,
    /// since a window can't render past the screen's own bounds) — a flat "chip" across the top
    /// of what should be a full circle, only ever visible on the top dock for exactly that reason.
    let floatingDrop: CGFloat

    init(
        screen: CGRect, safeAreaTop: CGFloat, cameraWidth rawCameraWidth: CGFloat,
        menuBarHeight rawMenuBarHeight: CGFloat = 24
    ) {
        self.screen = screen

        let barHeight = rawMenuBarHeight.isFinite ? min(64, max(16, rawMenuBarHeight)) : 24
        isNotched = safeAreaTop.isFinite && safeAreaTop > 0 && rawCameraWidth.isFinite && rawCameraWidth > 0

        // A real camera always hangs the island flush from the top edge, sized to its own
        // housing. Every other case floats instead, regardless of edge.
        floatingGap = isNotched ? nil : max(4, (barHeight * 0.18).rounded())
        floatingDrop = isNotched ? 0 : 4

        // Only the real-camera case is ever actually read by the live app (NotchPanel reads
        // DockPlacement's own fixed circle size for every other case) — kept correct for that one
        // case; a sane, if unused, fallback otherwise.
        if isNotched {
            cameraHeight = min(max(0, max(safeAreaTop, barHeight)), 64)
            cameraWidth = min(max(0, rawCameraWidth), screen.width * 0.7)
        } else {
            cameraHeight = barHeight
            cameraWidth = barHeight
        }

        menuBarHeight = max(cameraHeight, barHeight)
    }

    /// The island floats instead of hanging from the top edge.
    var floats: Bool { floatingGap != nil }

    func hasSameMenuBar(as other: IslandGeometry) -> Bool {
        screen == other.screen && cameraWidth == other.cameraWidth
            && menuBarHeight == other.menuBarHeight && isNotched == other.isNotched
    }

    var collapsedSize: CGSize {
        CGSize(width: cameraWidth, height: cameraHeight)
    }

    /// Centered on the display, pinned to its top edge. No surfaceShift term — that only exists
    /// in vorssaint to lean a notice toward its wider side, and this app has no notices.
    func frame(for size: CGSize) -> CGRect {
        CGRect(
            x: screen.midX - size.width / 2,
            y: screen.maxY - floatingDrop - size.height,
            width: size.width, height: size.height
        )
    }
}
