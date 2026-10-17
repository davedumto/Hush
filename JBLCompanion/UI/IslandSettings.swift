import CoreGraphics
import Foundation

/// Reads/writes every user-adjustable geometry setting in one place. Each typed accessor clamps
/// through IslandSize/IslandCameraFit/IslandCapsuleFit's own initializers, so a hand-edited or
/// stale UserDefaults value always comes back in range — mirrors vorssaint-utils's approach of
/// clamping in the type's init rather than at each call site.
enum IslandSettings {
    /// Internal (not private) so SwiftUI call sites can bind @AppStorage directly to these same
    /// keys instead of duplicating the string literals.
    enum Key {
        static let size = "islandSize"
        static let customWidth = "islandCustomWidth"
        static let customHeight = "islandCustomHeight"
        static let silhouette = "islandSilhouette"
        static let capsuleFitWidth = "islandCapsuleFitWidth"
        static let capsuleFitHeight = "islandCapsuleFitHeight"
        static let capsuleFitDrop = "islandCapsuleFitDrop"
        static let cameraFitWidth = "islandCameraFitWidth"
        static let cameraFitHeight = "islandCameraFitHeight"
        static let hideMenuBarGap = "islandHideMenuBarGap"
        static let outline = "islandOutlineEnabled"
        static let chosenDisplayUUID = "islandChosenDisplayUUID"
        static let autoExpandOnConnect = "islandAutoExpandOnConnect"
        /// Per-display edge is stored under one key per display UUID, not a single shared key —
        /// design/DESIGN_GUIDE.md §6: "save edge and offset per display."
        static func dockEdge(forDisplayUUID uuid: String) -> String { "islandDockEdge.\(uuid)" }
        /// Offset is further keyed by edge, not just display: a horizontal (top/bottom) offset
        /// and a vertical (left/right) one aren't the same number along the same axis, so one
        /// display switching edges must never apply the old edge's raw offset to the new one.
        static func dockOffset(forDisplayUUID uuid: String, edge: DockEdge) -> String { "islandDockOffset.\(uuid).\(edge.rawValue)" }
    }

    static var size: IslandSize {
        get { IslandSize(rawValue: UserDefaults.standard.string(forKey: Key.size) ?? "") ?? .compact }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.size) }
    }

    static var customWidth: Double {
        get { IslandSize.clamped(UserDefaults.standard.double(forKey: Key.customWidth), to: IslandSize.widthRange, fallback: IslandSize.defaultCustomWidth) }
        set { UserDefaults.standard.set(newValue, forKey: Key.customWidth) }
    }

    static var customHeight: Double {
        get { IslandSize.clamped(UserDefaults.standard.double(forKey: Key.customHeight), to: IslandSize.heightRange, fallback: IslandSize.defaultHeight) }
        set { UserDefaults.standard.set(newValue, forKey: Key.customHeight) }
    }

    static var silhouette: IslandSilhouette {
        get { IslandSilhouette(rawValue: UserDefaults.standard.string(forKey: Key.silhouette) ?? "") ?? .capsule }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.silhouette) }
    }

    static var capsuleFit: IslandCapsuleFit {
        get {
            let defaults = UserDefaults.standard
            return IslandCapsuleFit(
                width: defaults.double(forKey: Key.capsuleFitWidth),
                height: defaults.double(forKey: Key.capsuleFitHeight),
                drop: defaults.double(forKey: Key.capsuleFitDrop)
            )
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(Double(newValue.width), forKey: Key.capsuleFitWidth)
            defaults.set(Double(newValue.height), forKey: Key.capsuleFitHeight)
            defaults.set(Double(newValue.drop), forKey: Key.capsuleFitDrop)
        }
    }

    static var cameraFit: IslandCameraFit {
        get {
            let defaults = UserDefaults.standard
            return IslandCameraFit(width: defaults.double(forKey: Key.cameraFitWidth), height: defaults.double(forKey: Key.cameraFitHeight))
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(Double(newValue.width), forKey: Key.cameraFitWidth)
            defaults.set(Double(newValue.height), forKey: Key.cameraFitHeight)
        }
    }

    static var hideMenuBarGap: Bool {
        get { UserDefaults.standard.object(forKey: Key.hideMenuBarGap) == nil ? true : UserDefaults.standard.bool(forKey: Key.hideMenuBarGap) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hideMenuBarGap) }
    }

    static var outlineEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.outline) }
        set { UserDefaults.standard.set(newValue, forKey: Key.outline) }
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
