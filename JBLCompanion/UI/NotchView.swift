import SwiftUI

/// Transient presentation state for the notch panel (expanded/collapsed). Deliberately separate
/// from HeadphoneState, which is device state, not UI state.
@Observable
@MainActor
final class NotchUIState {
    var isExpanded: Bool = false
}

/// Just the island's content — collapsed glyph+ring or the expanded card. The shape itself
/// (silhouette, resize animation) is NotchSilhouetteView, a native CAShapeLayer-backed view this
/// sits on top of; NotchView never draws its own background or shape.
struct NotchView: View {
    let state: HeadphoneState
    let uiState: NotchUIState
    let collapsedSize: CGSize
    let onSelectNoiseMode: (CommandableNoiseMode) -> Void
    /// Per-mode "is this command frame hardware-verified" check (Tune770NCProfile.isModeVerified)
    /// — only verified modes' segments are tappable. Off has no command frame at all (none has
    /// ever been captured), so its segment stays visible but permanently disabled rather than
    /// disappearing — see NoiseControlCommander.commandFrame's doc comment.
    let isModeVerified: (CommandableNoiseMode) -> Bool
    /// Whether the connected device's own model has noise control wired up at all
    /// (DeviceProfile.supportsNoiseControl) — false hides the segmented control entirely in favor
    /// of a "not available" message, distinct from a verified-but-disabled segment.
    let supportsNoiseControl: () -> Bool

    /// JBL's own brand orange — used sparingly, as the one accent color against the black shape.
    private let accent = Color(red: 1.0, green: 0.45, blue: 0.05)

    var body: some View {
        Group {
            if uiState.isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var collapsedContent: some View {
        Image(systemName: "headphones")
            .font(.system(size: min(collapsedSize.width, collapsedSize.height) * 0.5, weight: .medium))
            .foregroundStyle(state.connection == .connected ? accent : .gray)
            .frame(width: collapsedSize.width, height: collapsedSize.height)
    }

    /// "--" for an untrusted 0% reading (BatteryReadingPolicy) — distinct from "—", which means no
    /// reading at all.
    private var batteryDisplayText: String {
        if state.batteryPercentIsUnverifiedZero { return "--" }
        return state.batteryPercent.map { "\($0)%" } ?? "—"
    }

    private var batteryRingColor: Color {
        guard let percent = state.batteryPercent else { return .white }
        return percent > 20 ? .green : .red
    }

    private var batteryIconName: String {
        guard let percent = state.batteryPercent else { return "battery.0" }
        switch percent {
        case ..<15: return "battery.0"
        case 15..<40: return "battery.25"
        case 40..<65: return "battery.50"
        case 65..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().overlay(Color.white.opacity(0.1))
            noiseControlSection
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: "headphones")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.deviceName.isEmpty ? "No device" : state.deviceName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 4) {
                    Image(systemName: batteryIconName)
                        .font(.system(size: 11))
                        .foregroundStyle(batteryRingColor)
                    Text(batteryDisplayText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var noiseControlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOISE CONTROL")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.4))

            if state.connection == .connected && !supportsNoiseControl() {
                Text("Controls not available for this model yet")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                modeSegments
                statusCaption
            }
        }
    }

    /// A hand-built segmented control, not SwiftUI's native `.pickerStyle(.segmented)` — that
    /// style can only enable/disable the whole control at once, and individual segments need to
    /// be independently disabled here based on `isModeVerified`.
    @ViewBuilder
    private var modeSegments: some View {
        let selected = state.pendingNoiseMode ?? state.noiseMode.commandable
        HStack(spacing: 2) {
            ForEach(CommandableNoiseMode.allCases, id: \.self) { mode in
                let verified = isModeVerified(mode)
                let isSelected = selected == mode
                Button {
                    onSelectNoiseMode(mode)
                } label: {
                    Text(segmentLabel(mode))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.black : .white.opacity(verified ? 0.85 : 0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? accent : Color.white.opacity(0.001), // near-invisible but still hit-testable
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(state.pendingNoiseMode != nil || !verified)
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func segmentLabel(_ mode: CommandableNoiseMode) -> String {
        switch mode {
        case .off: return "Off"
        case .anc: return "ANC"
        case .talkThru: return "TalkThru"
        case .ambientAware: return "Ambient"
        }
    }

    @ViewBuilder
    private var statusCaption: some View {
        switch (state.pendingNoiseMode, state.noiseModeConfirmationTimedOut) {
        case (.some(let pending), _):
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(accent)
                Text("Setting \(pending.displayText)…")
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
            }
        case (nil, true):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text("No confirmation")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.orange)
        case (nil, false):
            Text(NoiseModeStatusText.format(mode: state.noiseMode, eventMapVerified: state.noiseModeEventMapVerified))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
