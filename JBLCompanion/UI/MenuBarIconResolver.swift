import Foundation

/// Which `MenuBar*` template asset the fallback NSStatusItem's button should show —
/// design/DESIGN_GUIDE.md §7's own dot-state table (solid = ANC, ring = Ambient, no dot = Off,
/// faint dot = no device), mapped onto the actual named assets instead of hand-drawn dots. Pure:
/// takes exactly the two facts that matter so AppDelegate can call it directly off HeadphoneState
/// with no extra plumbing.
///
/// `confirmedMode` means exactly that — CLAUDE.md: "A mode is shown as active only after a 5C
/// status event. A 5B ack alone is never confirmation," so this reads `HeadphoneState.noiseMode`
/// only, never `pendingNoiseMode`.
enum MenuBarIconResolver {
    static let anc = "MenuBarANC"
    static let ambient = "MenuBarAmbient"
    static let off = "MenuBarOff"
    static let noDevice = "MenuBarNoDevice"

    static func assetName(connection: ConnectionState, confirmedMode: NoiseMode) -> String {
        guard connection == .connected else { return noDevice }
        switch confirmedMode {
        case .anc: return anc
        case .ambientAware: return ambient
        case .off: return off
        // No MenuBarTalkThru asset exists yet — reuses the ANC asset, per the task's own
        // "unless a TalkThru asset exists" — revisit this mapping if one is ever added.
        case .talkThru: return anc
        // No confirmed status event has arrived yet since connecting (or none ever will, for an
        // unmatched/unknown profile) — same treatment as not connected at all.
        case .unknown: return noDevice
        }
    }
}
