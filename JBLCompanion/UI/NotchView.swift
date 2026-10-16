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
        ZStack {
            if state.connection == .connected {
                Circle()
                    .stroke(batteryRingColor, lineWidth: 2)
                    .padding(2)
            }
            Image(systemName: "headphones")
                .font(.system(size: min(collapsedSize.width, collapsedSize.height) * 0.5))
                .foregroundStyle(state.connection == .connected ? .white : .gray)
        }
        .frame(width: collapsedSize.width, height: collapsedSize.height)
    }

    private var batteryRingColor: Color {
        guard let percent = state.batteryPercent else { return .white }
        return percent > 20 ? .green : .red
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.deviceName.isEmpty ? "No device" : state.deviceName)
                .font(.headline)
                .foregroundStyle(.white)

            Text(state.batteryPercent.map { "\($0)%" } ?? "—")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

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
            .disabled(state.pendingNoiseMode != nil)

            statusCaption

            HStack(spacing: 6) {
                Text("TalkThru")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Text("soon")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var statusCaption: some View {
        if let pending = state.pendingNoiseMode {
            Text("Pending: \(pending.displayText)…")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        } else if state.noiseModeConfirmationTimedOut {
            Text("No confirmation")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else {
            Text("Noise mode: \(state.noiseMode.displayText)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
