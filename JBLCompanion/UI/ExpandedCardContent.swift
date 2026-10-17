import Foundation

/// Which edge the expanded card is docked to — design/DESIGN_GUIDE.md §4/§6. Only top is reachable
/// from the live app today (see ExpandedCard's own doc comment); bottom/left/right exist for the
/// pure logic, the custom tab Shape, and previews.
enum CardDock: Equatable {
    case top, bottom, left, right

    var isVertical: Bool {
        self == .left || self == .right
    }
}

/// The card's text/battery-chip content for a connected, "normal-layout" card (§4 "Name block") —
/// `CardConditionResolver` handles everything about `.noDevice`/`.connecting` (including their own
/// name-block text and the footer, which applies regardless of condition) before this is ever
/// reached, so there's no disconnected branch here anymore.
struct ExpandedCardContent: Equatable {
    enum BatteryChip: Equatable {
        case none
        case normal(percent: Int)
        case low(percent: Int)
    }

    let batteryChip: BatteryChip
    let subtitleText: String

    /// The hero's giant background number (§4) is just the digits — "770", not the chip's full
    /// "770NC" — e.g. `heroNumberText(from: "770NC") == "770"`.
    static func heroNumberText(from modelNumberText: String) -> String {
        String(modelNumberText.filter(\.isNumber))
    }

    static func resolve(batteryPercent: Int?) -> ExpandedCardContent {
        let batteryChip: BatteryChip
        if let percent = batteryPercent {
            // Shares PillVariant's own threshold constant rather than redefining "under 15%" here.
            batteryChip = percent < PillVariant.lowBatteryThreshold ? .low(percent: percent) : .normal(percent: percent)
        } else {
            batteryChip = .none
        }

        let isLow: Bool
        if case .low = batteryChip { isLow = true } else { isLow = false }

        return ExpandedCardContent(batteryChip: batteryChip, subtitleText: isLow ? "Connected · battery low" : "Connected")
    }
}
