import Foundation

/// Which physical edge the pill is docked to. Only the orientation (horizontal vs vertical) and
/// whether it's the notch-fused special case actually change the pill's own rendering —
/// design/DESIGN_GUIDE.md §3/§6. The real app only ever docks to the top today (NotchPanel has no
/// left/right/bottom placement logic yet), so `.bottom`/`.left`/`.right` exist for the pure
/// resolver/previews but aren't reachable from live app state — see CollapsedPill's own doc
/// comment.
enum PillDock: Equatable {
    case top(isNotched: Bool)
    case bottom
    case left
    case right

    var isVertical: Bool {
        switch self {
        case .left, .right: return true
        case .top, .bottom: return false
        }
    }

    var isNotch: Bool {
        if case .top(let isNotched) = self { return isNotched }
        return false
    }
}

/// The pill's own connection signal. Separate from HeadphoneState.ConnectionState because the
/// pill also needs "connecting" (design/DESIGN_GUIDE.md §3's Conditions table), which
/// HeadphoneState doesn't model yet — the real app never actually produces `.connecting` today
/// (see CollapsedPill's doc comment), only `.connected`.
enum PillConnectionState: Equatable {
    case connecting
    case connected
}

/// SwiftUI's ColorScheme has no bearing on PillVariant.resolve's own purity (it's a plain,
/// freely-constructible two-case enum), but this mirrors it 1:1 so PillVariant.swift stays
/// framework-free like the rest of this codebase's pure logic — the view converts
/// `@Environment(\.colorScheme)` to this at the call site.
enum PillTheme: Equatable {
    case light
    case dark
}

/// What's actually connected, from the pill's point of view — exactly what the UI layer has
/// available (HeadphoneState.photoAssetNames), not a DeviceProfile instance, which the UI layer
/// never holds (see AppDelegate.ActiveDeviceSession).
enum PillDeviceState: Equatable {
    case noDevice
    /// `photo == nil` means a profile matched but has no photographable product shot — CLAUDE.md:
    /// "Unknown JBL models use the generic mark with no photo."
    case matched(photo: HeadphonePhotoAssetNames?)
}

/// Everything CollapsedPill needs to render, resolved once (`resolve`) from the app's actual live
/// state so the view itself never branches on raw profile/connection/battery facts directly —
/// design/DESIGN_GUIDE.md §3.
struct PillVariant: Equatable {
    enum Photo: Equatable {
        /// Already the correct theme/notch-contrasted asset name — `resolve` makes that choice,
        /// never the view.
        case device(assetName: String)
        case genericMark
        case noDevice
    }

    enum Battery: Equatable {
        case none
        case bar(percent: Int, isLow: Bool)
        case spinner
    }

    let dock: PillDock
    /// The *effective* theme already accounts for the notch override (§3: "always BrandBlack in
    /// both themes") — never the raw input theme.
    let theme: PillTheme
    let photo: Photo
    let photoOpacity: Double
    let battery: Battery

    /// design/DESIGN_GUIDE.md §3 "Low battery (under 15%)" and §10's "Low battery threshold |
    /// under 15%" — 15 itself is NOT low, only strictly below it.
    static let lowBatteryThreshold = 15

    static func resolve(
        device: PillDeviceState,
        connection: PillConnectionState,
        batteryPercent: Int?,
        theme: PillTheme,
        dock: PillDock
    ) -> PillVariant {
        let effectiveTheme: PillTheme = dock.isNotch ? .dark : theme

        guard case .matched(let photoNames) = device else {
            return PillVariant(dock: dock, theme: effectiveTheme, photo: .noDevice, photoOpacity: 1, battery: .none)
        }

        // Contrast flip (§3): white headphones on the black pill, black headphones on the white
        // pill. The notch pill is always black (effectiveTheme already forces .dark for it), so
        // this one rule naturally also gives the notch its white headphones with no special case.
        let photo: Photo = photoNames.map { names in
            .device(assetName: effectiveTheme == .dark ? names.white : names.black)
        } ?? .genericMark

        if connection == .connecting {
            return PillVariant(dock: dock, theme: effectiveTheme, photo: photo, photoOpacity: 0.35, battery: .spinner)
        }

        guard let percent = batteryPercent else {
            return PillVariant(dock: dock, theme: effectiveTheme, photo: photo, photoOpacity: 1, battery: .none)
        }

        return PillVariant(
            dock: dock, theme: effectiveTheme, photo: photo, photoOpacity: 1,
            battery: .bar(percent: percent, isLow: percent < lowBatteryThreshold)
        )
    }
}
