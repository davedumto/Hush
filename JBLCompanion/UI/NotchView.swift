import SwiftUI

/// Transient presentation state for the notch panel (expanded/collapsed). Deliberately separate
/// from HeadphoneState, which is device state, not UI state.
@Observable
@MainActor
final class NotchUIState {
    var isExpanded: Bool = false
}

/// Exposes the current display's notch position to the menu's X/Y steppers.
@Observable
@MainActor
final class NotchPositionState {
    var position: NotchPosition = .defaultPosition
}

/// One shape that springs between a small collapsed circle and a larger expanded card.
struct NotchView: View {
    let state: HeadphoneState
    let uiState: NotchUIState
    let collapsedDiameter: CGFloat

    private let expandedSize = CGSize(width: 300, height: 120)

    var body: some View {
        RoundedRectangle(cornerRadius: uiState.isExpanded ? 24 : collapsedDiameter / 2, style: .continuous)
            .fill(Color.black)
            .frame(
                width: uiState.isExpanded ? expandedSize.width : collapsedDiameter,
                height: uiState.isExpanded ? expandedSize.height : collapsedDiameter
            )
            .overlay(alignment: .top) {
                if uiState.isExpanded {
                    expandedContent
                } else {
                    collapsedContent
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.78), value: uiState.isExpanded)
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
                .font(.system(size: collapsedDiameter * 0.5))
                .foregroundStyle(state.connection == .connected ? .white : .gray)
        }
        .frame(width: collapsedDiameter, height: collapsedDiameter)
    }

    private var batteryRingColor: Color {
        guard let percent = state.batteryPercent else { return .white }
        return percent > 20 ? .green : .red
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.deviceName.isEmpty ? "No device" : state.deviceName)
                .font(.headline)
                .foregroundStyle(.white)

            Text(state.batteryPercent.map { "\($0)%" } ?? "—")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Text("Noise mode: \(state.noiseMode.displayText)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            VStack(alignment: .leading, spacing: 6) {
                Toggle("ANC", isOn: .constant(false)).disabled(true)
                Toggle("Ambient Aware", isOn: .constant(false)).disabled(true)
                Toggle("TalkThru", isOn: .constant(false)).disabled(true)
            }
            .toggleStyle(.switch)
            .foregroundStyle(.white)

            Text("Coming soon")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .topLeading)
    }
}
