import Foundation

/// The expanded card's overall condition — design/DESIGN_GUIDE.md §5 "Conditions". Drives which
/// big layout variant ExpandedCard shows (normal / connecting / no-device); `controlsUnavailable`
/// and `lowBattery` are still a "normal" layout underneath (hero with photo+number, real mode
/// buttons or the note row, a status line) — they exist here so each has its own resolver case and
/// test, per the task, not because the view branches its whole layout on them. The battery chip's
/// own low/normal styling and the mode buttons' own note-row-vs-real-buttons choice are resolved
/// independently of this (ExpandedCardContent, ModeButtonResolver.hasWorkingControls) and stay
/// correct regardless of which single condition "wins" here.
enum CardCondition: Equatable {
    case noDevice
    case connecting
    case controlsUnavailable
    case lowBattery
    case connected

    /// False only for the two conditions that replace the mode-buttons area entirely (skeleton
    /// blocks, or the no-headphones action buttons) — used both by the view and by
    /// `CardConditionResolverTests.testNoTappableModeButtonWhileConnecting`.
    var showsModeButtons: Bool {
        switch self {
        case .noDevice, .connecting: return false
        case .controlsUnavailable, .lowBattery, .connected: return true
        }
    }
}

enum CardConditionResolver {
    /// - Parameters:
    ///   - classicConnected: `HeadphoneState.connection == .connected`.
    ///   - firstStatusEventReceived: `HeadphoneState.noiseMode != .unknown` — the RACE channel is
    ///     opened and listens for status on *any* matched profile (see AppDelegate's classic-
    ///     connect handler), so this is meaningful even for a profile with no verified commands.
    ///   - controlsAvailable: `ModeButtonResolver.hasWorkingControls(supportsNoiseControl:isModeVerified:)`.
    static func resolve(
        classicConnected: Bool, firstStatusEventReceived: Bool, batteryPercent: Int?, controlsAvailable: Bool
    ) -> CardCondition {
        guard classicConnected else { return .noDevice }
        guard firstStatusEventReceived else { return .connecting }
        guard controlsAvailable else { return .controlsUnavailable }
        if let batteryPercent, batteryPercent < PillVariant.lowBatteryThreshold { return .lowBattery }
        return .connected
    }

    /// Always "BLUETOOTH" (design/DESIGN_GUIDE.md §4 "Footer") — a function of `condition`, not a
    /// bare constant, so every piece of per-condition footer text lives in one place and the tests
    /// read naturally as "footer text for each condition" (the task's own wording).
    static func footerLeftText(for condition: CardCondition) -> String { "BLUETOOTH" }

    /// design/DESIGN_GUIDE.md §5 "No headphones": "Last seen: <last matched profile display
    /// name>" — nil (omit the line) when nothing has ever matched, or the name is somehow empty.
    static func lastSeenText(lastMatchedProfileDisplayName: String?) -> String? {
        guard let name = lastMatchedProfileDisplayName, !name.isEmpty else { return nil }
        return "Last seen: \(name)"
    }
}
