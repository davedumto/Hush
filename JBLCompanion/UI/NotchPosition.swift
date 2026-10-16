import CoreGraphics
import Foundation

/// A saved notch circle position, in a top-left-origin, y-increases-downward coordinate space
/// local to one display (NOT AppKit's bottom-left/y-up, global-desktop space — NotchPanel converts
/// at the one point where it actually builds an NSRect).
/// `x`: offset of the shape's left edge from that display's horizontal center.
/// `y`: offset of the shape's top edge from that display's top edge.
struct NotchPosition: Equatable, Codable {
    var x: Double
    var y: Double

    /// Matches the old fixed centered placement (140pt right of center, at the very top) so a
    /// display with no saved position behaves exactly as it did before this feature existed.
    static let defaultPosition = NotchPosition(x: 140, y: 0)
}

/// Pure clamping logic — no AppKit, no I/O.
enum PositionClamp {
    /// Clamps `position` so a shape of `shapeSize` stays fully within a display of `displaySize`,
    /// in the same coordinate space as `NotchPosition`. If the shape is wider than the display
    /// (degenerate case), centers it horizontally rather than producing an inverted range.
    static func clamp(_ position: NotchPosition, shapeSize: CGSize, displaySize: CGSize) -> NotchPosition {
        let halfWidth = Double(shapeSize.width) / 2
        let minX = halfWidth - Double(displaySize.width) / 2
        let maxX = Double(displaySize.width) / 2 - halfWidth
        let clampedX = minX > maxX ? 0 : position.x.jblClamped(to: minX...maxX)

        let maxY = max(Double(displaySize.height) - Double(shapeSize.height), 0)
        let clampedY = position.y.jblClamped(to: 0...maxY)

        return NotchPosition(x: clampedX, y: clampedY)
    }
}

/// Clamps an arbitrary rect's top-left origin (same coordinate convention as NotchPosition) so it
/// stays fully inside a display's bounds. Used to keep the expanded card on-screen even when the
/// collapsed circle it's anchored to sits right at an edge.
enum RectClamp {
    static func clampOrigin(_ origin: CGPoint, size: CGSize, within displaySize: CGSize) -> CGPoint {
        let maxX = max(Double(displaySize.width) - Double(size.width), 0)
        let maxY = max(Double(displaySize.height) - Double(size.height), 0)
        return CGPoint(
            x: Double(origin.x).jblClamped(to: 0...maxX),
            y: Double(origin.y).jblClamped(to: 0...maxY)
        )
    }
}

extension Double {
    func jblClamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Per-display persistence, keyed by each display's stable CGDisplayCreateUUIDFromDisplayID string
/// (so a saved position survives an external monitor being unplugged and reconnected, or macOS
/// renumbering displays — the UUID doesn't change, only the transient display ID does).
enum NotchPositionStore {
    static func key(forDisplayUUID uuid: String) -> String {
        "notchPosition.\(uuid)"
    }

    static func load(forDisplayUUID uuid: String, defaults: UserDefaults) -> NotchPosition? {
        guard let data = defaults.data(forKey: key(forDisplayUUID: uuid)) else { return nil }
        return try? JSONDecoder().decode(NotchPosition.self, from: data)
    }

    static func save(_ position: NotchPosition, forDisplayUUID uuid: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: key(forDisplayUUID: uuid))
    }

    static func reset(forDisplayUUID uuid: String, defaults: UserDefaults) {
        defaults.removeObject(forKey: key(forDisplayUUID: uuid))
    }
}
