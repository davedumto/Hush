import CoreGraphics
import Foundation

enum IslandSilhouette: String, CaseIterable, Codable {
    case capsule, notch
}

/// A floating capsule sized and placed by hand, shown only when there's no physical camera and
/// the capsule silhouette is chosen. Ported verbatim (clamping/rounding) from NotchCapsuleFit.
struct IslandCapsuleFit: Equatable, Codable {
    static let widthRange = -40.0...40.0
    static let heightRange = -4.0...4.0
    static let dropRange = 0.0...20.0
    static let zero = IslandCapsuleFit(width: 0, height: 0, drop: 0)

    let width: CGFloat
    let height: CGFloat
    let drop: CGFloat

    init(width: Double, height: Double, drop: Double) {
        self.width = (Self.clamped(width, to: Self.widthRange, fallback: 0) / 2).rounded() * 2
        self.height = Self.clamped(height, to: Self.heightRange, fallback: 0).rounded()
        self.drop = Self.clamped(drop, to: Self.dropRange, fallback: 0).rounded()
    }

    static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

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
    /// Nil hangs the island from the top edge (notch style). A capsule floats this far inside the
    /// menu bar, above and below itself.
    let floatingGap: CGFloat?
    let floatingDrop: CGFloat

    init(
        screen: CGRect, safeAreaTop: CGFloat, cameraWidth rawCameraWidth: CGFloat,
        menuBarHeight rawMenuBarHeight: CGFloat = 24,
        silhouette: IslandSilhouette = .capsule, capsuleFit: IslandCapsuleFit = .zero
    ) {
        self.screen = screen

        let barHeight = rawMenuBarHeight.isFinite ? min(64, max(16, rawMenuBarHeight)) : 24
        isNotched = safeAreaTop.isFinite && safeAreaTop > 0 && rawCameraWidth.isFinite && rawCameraWidth > 0

        // A capsule replaces only a simulated cutout — a real camera always hangs the island from
        // the top (notch style), regardless of the chosen silhouette.
        let gap: CGFloat? = !isNotched && silhouette == .capsule ? max(4, (barHeight * 0.18).rounded()) : nil
        floatingGap = gap
        let effectiveCapsuleFit = gap == nil ? IslandCapsuleFit.zero : capsuleFit
        floatingDrop = effectiveCapsuleFit.drop

        // Height first — the capsule's resting width (below) is sized relative to it, and it
        // doesn't depend on width itself either way. A real camera's housing is always at least
        // as tall as the menu bar itself, same as macOS's own menu bar does.
        if isNotched {
            cameraHeight = min(max(0, max(safeAreaTop, barHeight)), 64)
        } else {
            cameraHeight = max(barHeight + effectiveCapsuleFit.height, (gap ?? 0) * 2 + 12)
        }

        // Without a camera, a *notch*-style resting shape simulates a cutout 180pt wide, scaled
        // to the menu-bar height, so it reads as a real notch. A floating *capsule* is a
        // different thing entirely — a small status-bar pill, not a wide simulated notch — so it
        // gets its own compact width proportional to its own (small) height instead.
        let simulatedNotchWidth = 180 * barHeight / 32
        // A snug pill just barely wider than it is tall — close to how a normal status-bar icon
        // badge looks — not an elongated one with empty space around a small icon. Hard cap,
        // independent of this ratio: whatever a floating capsule computes to, it can never end
        // up more than 2x its own (small) height, or past 80pt outright. If this specific shape
        // ever shows up oversized again, that's proof it isn't this formula.
        let capsulePillWidth = min(cameraHeight * 1.3, cameraHeight * 2, 80)
        self.cameraWidth = min(
            isNotched ? max(0, rawCameraWidth)
                : (gap == nil ? simulatedNotchWidth : capsulePillWidth + effectiveCapsuleFit.width),
            screen.width * 0.7
        )

        menuBarHeight = max(cameraHeight, barHeight)
    }

    /// The island floats in the menu bar instead of hanging from the top edge.
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
