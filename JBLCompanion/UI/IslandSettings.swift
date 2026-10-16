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
}
