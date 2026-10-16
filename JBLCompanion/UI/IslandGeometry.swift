import CoreGraphics
import Foundation

/// Size preset for the island, ported from vorssaint-utils's NotchSize. Widths/heights differ
/// from vorssaint's own defaults — this app's content is much smaller, so the numbers here are
/// the brief's own (compact 480pt wide, spacious 560pt), not vorssaint's (440/480).
enum IslandSize: String, CaseIterable, Codable {
    case compact, spacious, custom

    static let widthRange = 360.0...600.0
    static let heightRange = 260.0...640.0
    static let compactWidth = 480.0
    static let spaciousWidth = 560.0
    static let defaultHeight = 480.0
    static let defaultCustomWidth = 440.0

    static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

enum IslandSilhouette: String, CaseIterable, Codable {
    case capsule, notch
}

/// A correction to the camera housing macOS reports, for notched displays only. Ported verbatim
/// (clamping/rounding) from vorssaint-utils's NotchCameraFit.
struct IslandCameraFit: Equatable, Codable {
    static let widthRange = -10.0...10.0
    static let heightRange = -6.0...6.0
    static let zero = IslandCameraFit(width: 0, height: 0)

    let width: CGFloat
    let height: CGFloat

    init(width: Double, height: Double) {
        self.width = IslandSize.clamped(width, to: Self.widthRange, fallback: 0).rounded()
        self.height = (IslandSize.clamped(height, to: Self.heightRange, fallback: 0) * 2).rounded() / 2
    }
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
        self.width = (IslandSize.clamped(width, to: Self.widthRange, fallback: 0) / 2).rounded() * 2
        self.height = IslandSize.clamped(height, to: Self.heightRange, fallback: 0).rounded()
        self.drop = IslandSize.clamped(drop, to: Self.dropRange, fallback: 0).rounded()
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
    let layout: IslandSize
    let customWidth: CGFloat
    let customHeight: CGFloat
    let menuBarHeight: CGFloat
    /// Nil hangs the island from the top edge (notch style). A capsule floats this far inside the
    /// menu bar, above and below itself.
    let floatingGap: CGFloat?
    let floatingDrop: CGFloat
    let outlineRoom: CGFloat

    init(
        screen: CGRect, safeAreaTop: CGFloat, cameraWidth rawCameraWidth: CGFloat, layout: IslandSize = .compact,
        menuBarHeight rawMenuBarHeight: CGFloat = 24, customWidth: Double = IslandSize.defaultCustomWidth,
        customHeight: Double = IslandSize.defaultHeight, cameraFit: IslandCameraFit = .zero,
        silhouette: IslandSilhouette = .capsule, capsuleFit: IslandCapsuleFit = .zero,
        hideMenuBarGap: Bool = true, outline: Bool = false
    ) {
        self.screen = screen
        self.layout = layout
        self.customWidth = IslandSize.clamped(customWidth, to: IslandSize.widthRange, fallback: IslandSize.defaultCustomWidth)
        self.customHeight = IslandSize.clamped(customHeight, to: IslandSize.heightRange, fallback: IslandSize.defaultHeight)

        let barHeight = rawMenuBarHeight.isFinite ? min(64, max(16, rawMenuBarHeight)) : 24
        isNotched = safeAreaTop.isFinite && safeAreaTop > 0 && rawCameraWidth.isFinite && rawCameraWidth > 0

        // Only a physical camera has an outline to match.
        let fit = isNotched ? cameraFit : .zero

        // A capsule replaces only a simulated cutout — a real camera always hangs the island from
        // the top (notch style), regardless of the chosen silhouette.
        let gap: CGFloat? = !isNotched && silhouette == .capsule ? max(4, (barHeight * 0.18).rounded()) : nil
        floatingGap = gap
        let effectiveCapsuleFit = gap == nil ? IslandCapsuleFit.zero : capsuleFit
        floatingDrop = effectiveCapsuleFit.drop

        let room: CGFloat = isNotched && outline ? 2 : 0
        outlineRoom = room

        // Height first — the capsule's resting width (below) is sized relative to it, and it
        // doesn't depend on width itself either way.
        if isNotched {
            let baseHeight = hideMenuBarGap ? max(safeAreaTop, barHeight) : safeAreaTop
            cameraHeight = min(max(0, baseHeight + fit.height + room), 64)
        } else {
            cameraHeight = max(barHeight + effectiveCapsuleFit.height, (gap ?? 0) * 2 + 12)
        }

        // Without a camera, a *notch*-style resting shape simulates a cutout 180pt wide, scaled
        // to the menu-bar height, so it reads as a real notch. A floating *capsule* is a
        // different thing entirely — a small status-bar pill, not a wide simulated notch — so it
        // gets its own compact width proportional to its own (small) height instead.
        let simulatedNotchWidth = 180 * barHeight / 32
        let capsulePillWidth = cameraHeight * 2.4
        self.cameraWidth = min(
            isNotched ? max(0, rawCameraWidth + fit.width + room * 2)
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

    var expandedWidth: CGFloat {
        let chosen: CGFloat
        switch layout {
        case .compact: chosen = IslandSize.compactWidth
        case .spacious: chosen = IslandSize.spaciousWidth
        case .custom: chosen = customWidth
        }
        // A floor of 100pt guards against a degenerate (e.g. zero-size) screen read ever
        // producing a negative or near-zero width.
        return max(100, min(max(chosen, cameraWidth + 36), screen.width - 24))
    }

    /// Height from the page's own content, capped at the screen and (when custom sizing is
    /// chosen) at the custom height.
    func expandedSize(contentHeight: CGFloat, topInset: CGFloat) -> CGSize {
        let heightCap = layout == .custom ? customHeight : IslandSize.defaultHeight
        let preferred = min(topInset + contentHeight, heightCap)
        return CGSize(width: expandedWidth, height: max(80, min(preferred, screen.height - 48)))
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
