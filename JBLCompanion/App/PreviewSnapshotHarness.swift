#if DEBUG
import AppKit
import SwiftUI

/// A DEBUG-only, headless way to render specific ExpandedCard/CollapsedPill states to PNG files on
/// disk, for comparing against design/reference/*.png without Xcode's interactive preview canvas
/// (not available to an automated build/test run). Checked first thing in
/// AppDelegate.applicationDidFinishLaunching, before anything else: if JBL_SNAPSHOT_DIR is set,
/// renders every scenario below and terminates immediately, never starting real Bluetooth/UI.
/// Not part of what ships to a real user — purely a development-time comparison tool.
@MainActor
enum PreviewSnapshotHarness {
    static func runIfRequested() -> Bool {
        guard let dir = ProcessInfo.processInfo.environment["JBL_SNAPSHOT_DIR"] else { return false }
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for scenario in scenarios {
            render(scenario, to: url)
        }
        return true
    }

    private struct Scenario {
        let name: String
        let colorScheme: ColorScheme
        let content: AnyView
    }

    private static func state(
        connected: Bool = true, battery: Int? = 82, hasPhoto: Bool = true,
        deviceName: String = "JBL Tune 770NC", modelNumber: String = "770NC",
        noiseMode: NoiseMode = .unknown, pendingNoiseMode: CommandableNoiseMode? = nil,
        timedOut: Bool = false, eventMapVerified: Bool = true
    ) -> HeadphoneState {
        let state = HeadphoneState()
        state.connection = connected ? .connected : .disconnected
        state.deviceName = connected ? deviceName : ""
        state.modelNumberText = connected && hasPhoto ? modelNumber : ""
        state.photoAssetNames = connected && hasPhoto ? HeadphonePhotoAssetNames(black: "Tune\(modelNumber.prefix(3))Black", white: "Tune\(modelNumber.prefix(3))White") : nil
        state.batteryPercent = battery
        state.noiseMode = noiseMode
        state.pendingNoiseMode = pendingNoiseMode
        state.noiseModeConfirmationTimedOut = timedOut
        state.noiseModeEventMapVerified = eventMapVerified
        return state
    }

    /// Matches Tune770NCProfile/Tune670NCProfile.isModeVerified exactly: Ambient, ANC, and
    /// TalkThru verified, Off never (no command frame has ever been captured for it) — real
    /// current profile state, not the design guide's now-outdated per-model disabled lists
    /// (CLAUDE.md overrides those).
    private static func matchedProfileIsModeVerified(_ mode: CommandableNoiseMode) -> Bool { mode != .off }

    private static var scenarios: [Scenario] {
        let s770 = state(noiseMode: .anc)
        let s670 = state(deviceName: "JBL Tune 670NC", modelNumber: "670NC", noiseMode: .anc)
        // Reuses s670's shape (battery 64, matching design/reference/03-04) rather than leaving
        // noiseMode at .unknown: that would make CardConditionResolver read this as "connecting"
        // instead of "connected with unavailable controls" (.unknown is specifically "no status
        // event yet", which is exactly what .connecting means) — there's no way to represent "a
        // status event arrived, reporting something no button maps to," since NoiseMode's only
        // non-.unknown cases are the four buttons themselves. So ANC renders active here, same as
        // the hardware-reported-Off case (ModeButtonResolverTests) — a deliberate, documented
        // difference from 03/04's static mockup (which shows nothing active at all): an active
        // mode is still truthfully hardware-confirmed even when the profile has no verified
        // *commands*, and CLAUDE.md's active rule has no carve-out for that.
        let controlsUnavailable = state(battery: 64, deviceName: "JBL Tune 670NC", modelNumber: "670NC", noiseMode: .anc)
        let pending = state(noiseMode: .anc, pendingNoiseMode: .ambientAware)
        let timedOut = state(noiseMode: .ambientAware, timedOut: true)
        let unverifiedEventMap = state(noiseMode: .anc, eventMapVerified: false)
        let lowBattery = state(battery: 9, noiseMode: .anc)
        // noiseMode defaults to .unknown — classic-connected with no status event yet is exactly
        // "connecting" (CardConditionResolver).
        let connecting = state()
        let noDevice = state(connected: false, battery: nil)

        // Two overloads, not one with default parameter values: a local function whose default
        // argument expression references an outer static member hits a real Swift compiler bug
        // ("closure captures '$base$' before it is declared") — hit once already earlier in this
        // file's history, worked around the same way there.
        func card(
            _ st: HeadphoneState, _ dock: CardDock,
            isModeVerified: @escaping (CommandableNoiseMode) -> Bool, supportsNoiseControl: Bool, lastSeen: String?
        ) -> AnyView {
            AnyView(ExpandedCard(
                state: st, dock: dock, onCollapseTapped: {}, isModeVerified: isModeVerified,
                supportsNoiseControl: supportsNoiseControl, onSelectNoiseMode: { _ in }, onReconnectTapped: {},
                onOpenBluetoothSettingsTapped: {}, lastMatchedProfileDisplayName: lastSeen
            ))
        }
        func card(_ st: HeadphoneState, _ dock: CardDock) -> AnyView {
            card(st, dock, isModeVerified: matchedProfileIsModeVerified, supportsNoiseControl: true, lastSeen: "JBL Tune 770NC")
        }
        func pill(_ st: HeadphoneState, _ dock: PillDock, connection: PillConnectionState = .connected, scheme: ColorScheme) -> AnyView {
            let variant = PillVariant.resolve(
                device: st.connection == .connected ? .matched(photo: st.photoAssetNames) : .noDevice,
                connection: connection, batteryPercent: st.batteryPercent,
                theme: scheme == .dark ? .dark : .light, dock: dock
            )
            return AnyView(CollapsedPill(variant: variant))
        }

        return [
            Scenario(name: "card-01-top-770-dark", colorScheme: .dark, content: card(s770, .top)),
            Scenario(name: "card-02-top-770-light", colorScheme: .light, content: card(s770, .top)),
            Scenario(name: "card-05-top-770-dark-ambient-pending", colorScheme: .dark, content: card(pending, .top)),
            Scenario(name: "card-06-top-770-light-ambient-pending", colorScheme: .light, content: card(pending, .top)),
            Scenario(name: "card-09-top-770-dark-timed-out-kept-mode", colorScheme: .dark, content: card(timedOut, .top)),
            Scenario(name: "card-unverified-eventmap-dark", colorScheme: .dark, content: card(unverifiedEventMap, .top)),
            Scenario(name: "card-08-unverified-eventmap-light", colorScheme: .light, content: card(unverifiedEventMap, .top)),
            Scenario(name: "card-32-bottom-770-dark", colorScheme: .dark, content: card(s770, .bottom)),
            Scenario(name: "card-bottom-770-light", colorScheme: .light, content: card(s770, .bottom)),
            Scenario(name: "card-31-left-770-dark", colorScheme: .dark, content: card(s770, .left)),
            Scenario(name: "card-30-left-770-light", colorScheme: .light, content: card(s770, .left)),
            Scenario(name: "card-right-770-dark", colorScheme: .dark, content: card(s770, .right)),
            Scenario(name: "card-right-770-light", colorScheme: .light, content: card(s770, .right)),
            Scenario(name: "card-03-top-670-dark", colorScheme: .dark, content: card(s670, .top)),
            // 670NC, light, connected, with its own real verified-mode set (matchedProfileIsModeVerified
            // — mode != .off — exactly Tune670NCProfile.isModeVerified's own hardware-verified data,
            // not a stand-in) — the only existing 670-light scenario before this was controlsUnavailable
            // (all four modes forced unverified), which isn't what this model's real profile reports.
            Scenario(name: "card-670-light-working-controls", colorScheme: .light, content: card(s670, .top)),
            Scenario(name: "card-lowbattery-dark", colorScheme: .dark, content: card(lowBattery, .top)),
            Scenario(name: "card-lowbattery-light", colorScheme: .light, content: card(lowBattery, .top)),
            Scenario(name: "card-19-connecting-dark", colorScheme: .dark, content: card(connecting, .top)),
            Scenario(name: "card-27-connecting-light", colorScheme: .light, content: card(connecting, .top)),
            Scenario(name: "card-20-nodevice-dark", colorScheme: .dark, content: card(noDevice, .top, isModeVerified: { _ in false }, supportsNoiseControl: true, lastSeen: "JBL Tune 770NC")),
            Scenario(name: "card-28-nodevice-light", colorScheme: .light, content: card(noDevice, .top, isModeVerified: { _ in false }, supportsNoiseControl: true, lastSeen: "JBL Tune 770NC")),
            Scenario(name: "card-nodevice-never-matched-dark", colorScheme: .dark, content: card(noDevice, .top, isModeVerified: { _ in false }, supportsNoiseControl: true, lastSeen: nil)),
            Scenario(name: "card-nodevice-side-dock-dark", colorScheme: .dark, content: card(noDevice, .left, isModeVerified: { _ in false }, supportsNoiseControl: true, lastSeen: "JBL Tune 770NC")),
            Scenario(name: "card-03-controls-unavailable-dark", colorScheme: .dark, content: card(controlsUnavailable, .top, isModeVerified: { _ in false }, supportsNoiseControl: false, lastSeen: "JBL Tune 770NC")),
            Scenario(name: "card-04-controls-unavailable-light", colorScheme: .light, content: card(controlsUnavailable, .top, isModeVerified: { _ in false }, supportsNoiseControl: false, lastSeen: "JBL Tune 770NC")),
            Scenario(name: "pill-15-variants-dark", colorScheme: .dark, content: pill(s770, .top(isNotched: false), scheme: .dark)),
            Scenario(name: "pill-16-variants-light", colorScheme: .light, content: pill(s770, .top(isNotched: false), scheme: .light)),
            Scenario(name: "pill-notch-dark", colorScheme: .dark, content: pill(s770, .top(isNotched: true), scheme: .dark)),
            Scenario(name: "pill-connecting-dark", colorScheme: .dark, content: pill(connecting, .top(isNotched: false), connection: .connecting, scheme: .dark)),
            Scenario(name: "pill-bottom-dark", colorScheme: .dark, content: pill(s770, .bottom, scheme: .dark)),
            Scenario(name: "pill-bottom-light", colorScheme: .light, content: pill(s770, .bottom, scheme: .light)),
            Scenario(name: "pill-left-dark", colorScheme: .dark, content: pill(s770, .left, scheme: .dark)),
            Scenario(name: "pill-left-light", colorScheme: .light, content: pill(s770, .left, scheme: .light)),
            Scenario(name: "pill-right-dark", colorScheme: .dark, content: pill(s770, .right, scheme: .dark)),
            Scenario(name: "pill-right-light", colorScheme: .light, content: pill(s770, .right, scheme: .light)),
            Scenario(name: "zzz-icon-closeup", colorScheme: .dark, content: AnyView(
                HStack(spacing: 16) {
                    iconCloseup("IconSettings")
                    iconCloseup("IconPower")
                    iconCloseup("IconPlus")
                }
            )),
        ]
    }

    private static func iconCloseup(_ name: String) -> some View {
        Circle()
            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            .frame(width: 100, height: 100)
            .overlay(
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 50)
                    .foregroundStyle(.white)
            )
    }

    private static func render(_ scenario: Scenario, to dir: URL) {
        let host = scenario.content
            .padding(40)
            .background(scenario.colorScheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scenario.colorScheme)
        let renderer = ImageRenderer(content: host)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("FAILED to render \(scenario.name)\n".data(using: .utf8)!)
            return
        }
        let url = dir.appendingPathComponent("\(scenario.name).png")
        try? png.write(to: url)
    }
}
#endif
