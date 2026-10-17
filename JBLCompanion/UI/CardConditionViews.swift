import SwiftUI

/// Small view pieces specific to the expanded card's non-normal conditions (design/DESIGN_GUIDE.md
/// §5) — the normal/controlsUnavailable/lowBattery layout stays entirely inside ExpandedCard
/// itself (hero, name block, ModeButtonsSection), since only `.connecting` and `.noDevice` need
/// genuinely different content here.

// MARK: - Connecting (§5 "Connecting", §9.4 "Pulsing status dot")

/// Four shimmering skeleton blocks standing in for the mode buttons, plus the "Reading mode from
/// headphones…" status line. Same row/column layout as the real `ModeButtonsSection` so the swap
/// (§9.5: "skeletons crossfade into the real buttons") lines up without a layout jump.
struct ConnectingPlaceholder: View {
    let dock: CardDock

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerOn = false

    private var isVertical: Bool { dock.isVertical }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            skeletonBlocks
            HStack(spacing: 7) {
                ConnectingPulsingDot()
                Text("Reading mode from headphones…")
                    .font(Theme.Fonts.statusDetail)
                    .foregroundStyle(Theme.Semantic.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var skeletonBlocks: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
            : AnyLayout(HStackLayout(spacing: 6))
        layout {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(shimmerOn ? 0.16 : 0.07))
                    .frame(maxWidth: .infinity)
                    .frame(height: isVertical ? 40 : 52)
            }
        }
        // §9.4: "A simple opacity pulse between white 7% and 16% at 0.75s is an acceptable
        // substitute" for the sweeping-band shimmer. Not in §9.6's exempt list (only the pending
        // ring fill and the connecting spinner are), so it stops under Reduce Motion.
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: MotionConstants.skeletonShimmerHalfCycle).repeatForever(autoreverses: true)
            ) { shimmerOn = true }
        }
    }
}

/// §9.4 "Pulsing status dot": opacity 0.3 to 1 and back, 1.1s cycle. Not named in §9.6's exempt
/// list (only the pending ring fill and the connecting spinner are) — unlike
/// `ModeButtonsSection.PendingRingView`, this carries no information the 11pt chip spinner (which
/// *is* exempt) doesn't already convey, so it correctly stops under Reduce Motion rather than
/// needing its own exemption.
struct ConnectingPulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBright = false

    var body: some View {
        Circle()
            .strokeBorder(Theme.Brand.orange, lineWidth: 1.7)
            .frame(width: 7, height: 7)
            .opacity(reduceMotion ? 1 : (isBright ? 1 : 0.3))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: MotionConstants.pulsingStatusDotHalfCycle).repeatForever(autoreverses: true)
                ) { isBright = true }
            }
    }
}

/// §9.4 "Connecting spinner": 11pt ring, 1.7 stroke, track orange 25%, a 28% arc in full orange,
/// 360° every 0.8s. Exempt from Reduce Motion (§9.6 names it explicitly) — always spins.
struct ConnectingSpinner: View {
    var size: CGFloat = 11
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Brand.orange.opacity(0.25), lineWidth: 1.7)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Theme.Brand.orange, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(rotation))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(
                .linear(duration: MotionConstants.connectingSpinnerRevolution).repeatForever(autoreverses: false)
            ) { rotation = 360 }
        }
    }
}

// MARK: - No headphones (§5 "No headphones")

/// The helper sentence plus the Reconnect / Bluetooth Settings button pair that replace the mode
/// buttons and status line entirely once there's no device at all.
struct NoHeadphonesActions: View {
    let dock: CardDock
    let onReconnectTapped: () -> Void
    let onOpenBluetoothSettingsTapped: () -> Void

    private var isVertical: Bool { dock.isVertical }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Turn your headphones on and they show up here. First time? Pair them in Bluetooth settings.")
                .font(Theme.Fonts.subText)
                .foregroundStyle(Theme.Semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            let layout = isVertical
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Button(action: onReconnectTapped) {
                    Text("Reconnect")
                        .font(Theme.Fonts.modeLabel())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Theme.Brand.orange, in: Capsule())
                        .shadow(color: Theme.Brand.orange.opacity(0.7), radius: 10, x: 0, y: 8)
                }
                .buttonStyle(.plain)

                Button(action: onOpenBluetoothSettingsTapped) {
                    Text("Bluetooth Settings")
                        .font(Theme.Fonts.modeLabel())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .overlay(Capsule().strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
