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

    private static func state(connected: Bool = true, battery: Int? = 82, hasPhoto: Bool = true, deviceName: String = "JBL Tune 770NC", modelNumber: String = "770NC") -> HeadphoneState {
        let state = HeadphoneState()
        state.connection = connected ? .connected : .disconnected
        state.deviceName = connected ? deviceName : ""
        state.modelNumberText = connected && hasPhoto ? modelNumber : ""
        state.photoAssetNames = connected && hasPhoto ? HeadphonePhotoAssetNames(black: "Tune\(modelNumber.prefix(3))Black", white: "Tune\(modelNumber.prefix(3))White") : nil
        state.batteryPercent = battery
        return state
    }

    private struct SlotStub: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("NOISE CONTROL")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.4))
                HStack(spacing: 2) {
                    ForEach(["Off", "ANC", "Ambient", "TalkThru"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(label == "ANC" ? .black : .white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(label == "ANC" ? Color(red: 1.0, green: 0.40, blue: 0.0) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 1.0, green: 0.40, blue: 0.0)).frame(width: 7, height: 7)
                    Text("ANC").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    Text("set by headphones").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private static var scenarios: [Scenario] {
        let s770 = state()
        let s670 = state(deviceName: "JBL Tune 670NC", modelNumber: "670NC")
        let lowBattery = state(battery: 9)
        let noDevice = state(connected: false, battery: nil)

        func card(_ st: HeadphoneState, _ dock: CardDock) -> AnyView {
            AnyView(ExpandedCard(state: st, dock: dock, onCollapseTapped: {}) { SlotStub() })
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
            Scenario(name: "card-32-bottom-770-dark", colorScheme: .dark, content: card(s770, .bottom)),
            Scenario(name: "card-31-left-770-dark", colorScheme: .dark, content: card(s770, .left)),
            Scenario(name: "card-30-left-770-light", colorScheme: .light, content: card(s770, .left)),
            Scenario(name: "card-03-top-670-dark", colorScheme: .dark, content: card(s670, .top)),
            Scenario(name: "card-lowbattery-dark", colorScheme: .dark, content: card(lowBattery, .top)),
            Scenario(name: "card-nodevice-dark", colorScheme: .dark, content: card(noDevice, .top)),
            Scenario(name: "pill-15-variants-dark", colorScheme: .dark, content: pill(s770, .top(isNotched: false), scheme: .dark)),
            Scenario(name: "pill-16-variants-light", colorScheme: .light, content: pill(s770, .top(isNotched: false), scheme: .light)),
            Scenario(name: "pill-notch-dark", colorScheme: .dark, content: pill(s770, .top(isNotched: true), scheme: .dark)),
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
