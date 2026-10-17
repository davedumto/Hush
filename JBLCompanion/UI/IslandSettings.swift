import CoreGraphics
import Foundation

/// Reads/writes every user-adjustable geometry setting in one place. Each typed accessor clamps
/// to its own valid range, so a hand-edited or stale UserDefaults value always comes back usable.
enum IslandSettings {
    /// Internal (not private) so SwiftUI call sites can bind @AppStorage directly to these same
    /// keys instead of duplicating the string literals.
    enum Key {
        static let pillDiameter = "islandPillDiameter"
        static let chosenDisplayUUID = "islandChosenDisplayUUID"
        static let autoExpandOnConnect = "islandAutoExpandOnConnect"
        /// One key per edge (not per display, unlike dockEdge/dockOffset below) — a "how far from
        /// the top" preference is about the edge itself, not which physical display it's on.
        static func edgeMargin(for edge: DockEdge) -> String { "islandEdgeMargin.\(edge.rawValue)" }
        /// Per-display edge is stored under one key per display UUID, not a single shared key —
        /// design/DESIGN_GUIDE.md §6: "save edge and offset per display."
        static func dockEdge(forDisplayUUID uuid: String) -> String { "islandDockEdge.\(uuid)" }
        /// Offset is further keyed by edge, not just display: a horizontal (top/bottom) offset
        /// and a vertical (left/right) one aren't the same number along the same axis, so one
        /// display switching edges must never apply the old edge's raw offset to the new one.
        static func dockOffset(forDisplayUUID uuid: String, edge: DockEdge) -> String { "islandDockOffset.\(uuid).\(edge.rawValue)" }
    }

    /// The collapsed pill's own diameter — a circle, the same on every edge. 0 (UserDefaults'
    /// default for an unset key) falls back to DockPlacement's own default rather than clamping
    /// down to the range's floor, so a user who's never touched this setting gets the designed
    /// default (52), not 40.
    static var pillDiameter: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: Key.pillDiameter)
            guard stored != 0 else { return DockPlacement.collapsedPillDiameter }
            return min(DockPlacement.pillDiameterRange.upperBound, max(DockPlacement.pillDiameterRange.lowerBound, stored))
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: Key.pillDiameter) }
    }

    /// How far the island sits from `edge` — top/bottom/left/right each keep their own value. 0
    /// (UserDefaults' default for an unset key) falls back to DockPlacement's own default rather
    /// than clamping down to the range's floor, same reasoning as `pillDiameter` above.
    static func edgeMargin(for edge: DockEdge) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: Key.edgeMargin(for: edge))
        guard stored != 0 else { return DockPlacement.edgeMargin(for: edge) }
        return min(DockPlacement.edgeMarginRange.upperBound, max(DockPlacement.edgeMarginRange.lowerBound, stored))
    }

    static func setEdgeMargin(_ margin: CGFloat, for edge: DockEdge) {
        UserDefaults.standard.set(Double(margin), forKey: Key.edgeMargin(for: edge))
    }

    /// nil means "automatic" — the display currently hosting the menu bar.
    static var chosenDisplayUUID: String? {
        get { UserDefaults.standard.string(forKey: Key.chosenDisplayUUID) }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: Key.chosenDisplayUUID) }
            else { UserDefaults.standard.removeObject(forKey: Key.chosenDisplayUUID) }
        }
    }

    /// design/DESIGN_GUIDE.md §5 "Connecting"'s own trigger — off by default: expanding on every
    /// connect is a bigger behavior change than this task's scope, so it's opt-in, not assumed.
    static var autoExpandOnConnect: Bool {
        get { UserDefaults.standard.bool(forKey: Key.autoExpandOnConnect) }
        set { UserDefaults.standard.set(newValue, forKey: Key.autoExpandOnConnect) }
    }

    /// `.top` (the only edge reachable before this task) when nothing has been saved yet for this
    /// display.
    static func dockEdge(forDisplayUUID uuid: String) -> DockEdge {
        guard let raw = UserDefaults.standard.string(forKey: Key.dockEdge(forDisplayUUID: uuid)) else { return .top }
        return DockEdge(rawValue: raw) ?? .top
    }

    static func setDockEdge(_ edge: DockEdge, forDisplayUUID uuid: String) {
        UserDefaults.standard.set(edge.rawValue, forKey: Key.dockEdge(forDisplayUUID: uuid))
    }

    /// 0 (centered — §6: "Default is the middle of the edge") when nothing has been saved yet for
    /// this exact display+edge combination.
    static func dockOffset(forDisplayUUID uuid: String, edge: DockEdge) -> CGFloat {
        let key = Key.dockOffset(forDisplayUUID: uuid, edge: edge)
        guard UserDefaults.standard.object(forKey: key) != nil else { return 0 }
        return UserDefaults.standard.double(forKey: key)
    }

    static func setDockOffset(_ offset: CGFloat, forDisplayUUID uuid: String, edge: DockEdge) {
        UserDefaults.standard.set(Double(offset), forKey: Key.dockOffset(forDisplayUUID: uuid, edge: edge))
    }
}
