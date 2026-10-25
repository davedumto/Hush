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
        /// Whether the island is docked to an edge or freely placed, per display, same keying
        /// reasoning as dockEdge above.
        static func placementMode(forDisplayUUID uuid: String) -> String { "islandPlacementMode.\(uuid)" }
        static func freePositionX(forDisplayUUID uuid: String) -> String { "islandFreePositionX.\(uuid)" }
        static func freePositionY(forDisplayUUID uuid: String) -> String { "islandFreePositionY.\(uuid)" }
        /// Which corner (if any) the island is fused into, per display — same keying reasoning as
        /// `dockEdge`/`freePosition` above. Absent (not just an empty string) means "not corner-
        /// docked," not "docked to some default corner."
        static func dockedCorner(forDisplayUUID uuid: String) -> String { "islandDockedCorner.\(uuid)" }
        /// Owner spec, 2026-10-25: only meaningful on a display with a real camera notch — whether
        /// the top dock there is the fixed, fused NotchExtensionBar ("Notch") or the ordinary
        /// draggable/dockable island ("Island", everything this app had before that feature).
        static func notchAttachmentMode(forDisplayUUID uuid: String) -> String { "islandNotchAttachmentMode.\(uuid)" }
    }

    enum PlacementMode: String {
        case edge, free
    }

    /// Owner spec, 2026-10-25: "when we are on the default mac display that has a notch, one can
    /// set it to be in the notch from the island settings or be an island." `.notch` is the fused,
    /// fixed NotchExtensionBar; `.island` is the ordinary draggable/dockable behavior every other
    /// display already has, available on a notched display too for anyone who prefers it. Has no
    /// effect at all on a display without a real notch (NotchPanel only ever consults this when
    /// `geometry.isNotched` is already true).
    enum NotchAttachmentMode: String {
        case notch, island
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

    /// `.edge` (the only mode reachable before dragging was freed from the edges) when nothing
    /// has been saved yet for this display.
    static func placementMode(forDisplayUUID uuid: String) -> PlacementMode {
        guard let raw = UserDefaults.standard.string(forKey: Key.placementMode(forDisplayUUID: uuid)) else { return .edge }
        return PlacementMode(rawValue: raw) ?? .edge
    }

    static func setPlacementMode(_ mode: PlacementMode, forDisplayUUID uuid: String) {
        UserDefaults.standard.set(mode.rawValue, forKey: Key.placementMode(forDisplayUUID: uuid))
    }

    /// `.notch` (the new default behavior) when nothing has been saved yet for this display — the
    /// owner's own framing was "notch setting would be just this [current behavior]," i.e. Notch
    /// is the baseline a notched display starts in, not something to opt into.
    static func notchAttachmentMode(forDisplayUUID uuid: String) -> NotchAttachmentMode {
        guard let raw = UserDefaults.standard.string(forKey: Key.notchAttachmentMode(forDisplayUUID: uuid)) else { return .notch }
        return NotchAttachmentMode(rawValue: raw) ?? .notch
    }

    static func setNotchAttachmentMode(_ mode: NotchAttachmentMode, forDisplayUUID uuid: String) {
        UserDefaults.standard.set(mode.rawValue, forKey: Key.notchAttachmentMode(forDisplayUUID: uuid))
    }

    /// The island's own free-floating center point in screen coordinates, when
    /// `placementMode(forDisplayUUID:) == .free`. nil when nothing has been saved yet (never
    /// dragged off an edge on this display) — callers fall back to a sensible default (e.g. the
    /// screen's center) rather than treating (0, 0) as a real saved position.
    static func freePosition(forDisplayUUID uuid: String) -> CGPoint? {
        let xKey = Key.freePositionX(forDisplayUUID: uuid)
        let yKey = Key.freePositionY(forDisplayUUID: uuid)
        guard UserDefaults.standard.object(forKey: xKey) != nil, UserDefaults.standard.object(forKey: yKey) != nil else { return nil }
        return CGPoint(x: UserDefaults.standard.double(forKey: xKey), y: UserDefaults.standard.double(forKey: yKey))
    }

    static func setFreePosition(_ point: CGPoint, forDisplayUUID uuid: String) {
        UserDefaults.standard.set(Double(point.x), forKey: Key.freePositionX(forDisplayUUID: uuid))
        UserDefaults.standard.set(Double(point.y), forKey: Key.freePositionY(forDisplayUUID: uuid))
    }

    /// nil means "not corner-docked" — either never dragged into one on this display, or
    /// explicitly cleared by docking to a plain edge or going free.
    static func dockedCorner(forDisplayUUID uuid: String) -> ScreenCorner? {
        guard let raw = UserDefaults.standard.string(forKey: Key.dockedCorner(forDisplayUUID: uuid)) else { return nil }
        return ScreenCorner(rawValue: raw)
    }

    static func setDockedCorner(_ corner: ScreenCorner?, forDisplayUUID uuid: String) {
        if let corner {
            UserDefaults.standard.set(corner.rawValue, forKey: Key.dockedCorner(forDisplayUUID: uuid))
        } else {
            UserDefaults.standard.removeObject(forKey: Key.dockedCorner(forDisplayUUID: uuid))
        }
    }
}
