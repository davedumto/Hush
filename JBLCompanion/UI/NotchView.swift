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
            talkThruRow
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
                    Text(state.batteryPercent.map { "\($0)%" } ?? "—")
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

            // Selection always reflects the externally-confirmed/pending state, never a locally
            // stored "what the user just tapped" value — so a tap shows pending, not an
            // optimistic jump to the tapped mode.
            Picker("Noise control", selection: Binding<CommandableNoiseMode?>(
                get: { state.pendingNoiseMode ?? state.noiseMode.commandable },
                set: { newValue in
                    if let newValue { onSelectNoiseMode(newValue) }
                }
            )) {
                Text("Off").tag(Optional(CommandableNoiseMode.off))
                Text("ANC").tag(Optional(CommandableNoiseMode.anc))
                Text("Ambient").tag(Optional(CommandableNoiseMode.ambientAware))
            }
            .pickerStyle(.segmented)
            .tint(accent)
            .disabled(state.pendingNoiseMode != nil)

            statusCaption
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
            Text(state.noiseMode.displayText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    @ViewBuilder
    private var talkThruRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
            Text("TalkThru")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
            Text("SOON")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
    }
}
