import SwiftUI

/// The collapsed pill shown when the card isn't expanded — design/DESIGN_GUIDE.md §3. Purely a
/// function of `variant` (PillVariant.resolve) plus local hover state for the scale-up spring;
/// never branches on raw profile/connection/battery facts itself.
///
/// Renders at the guide's own fixed size (46x34, or 34x46 for a vertical dock) regardless of
/// whatever frame it's placed in — NotchView centers it inside `collapsedSize`, the surrounding
/// app's own adaptive capsule/notch sizing (IslandGeometry), which doesn't currently always equal
/// 46x34 on every display. The pill's own shape/fill/border/shadow are self-drawn (unlike
/// NotchView's other content, which never draws its own background — see its doc comment): the
/// native NotchSilhouetteView underneath is a fixed, always-black fill with no theme awareness, so
/// it can't produce the light theme's white pill or the per-condition border/glow on its own.
/// Because of that split, the pill's own shadow/glow can be clipped by the window's current
/// zero-margin framing at rest (NotchPanel has no reserved shadow margin for the collapsed size) —
/// a known limitation, out of scope for this task alongside the window-geometry work it would take
/// to fix.
struct CollapsedPill: View {
    let variant: PillVariant
    @State private var isHovering = false
    @State private var spinnerRotation: Double = 0
    @State private var lowBatteryPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isVertical: Bool { variant.dock.isVertical }
    private var size: CGSize {
        isVertical ? CGSize(width: 34, height: 46) : CGSize(width: 46, height: 34)
    }
    private var cornerRadius: CGFloat { min(size.width, size.height) / 2 }
    private var isLowBattery: Bool {
        if case .bar(_, let isLow) = variant.battery { return isLow }
        return false
    }

    var body: some View {
        ZStack {
            shape
            contentView
        }
        .frame(width: size.width, height: size.height)
        // §9.4 "Pill hover": "Scale to 1.06, spring response 0.32, damping 0.6." §9.6 doesn't name
        // pill hover among the loops/transitions it stops, and it's a direct response to a live
        // pointer position rather than a decorative idle loop, so it's left running under Reduce
        // Motion same as mode-button hover already is (ModeButtonsSection.ModeButtonView).
        .scaleEffect(isHovering ? MotionConstants.pillHoverScale : 1)
        .animation(
            .spring(response: MotionConstants.pillHoverSpringResponse, dampingFraction: MotionConstants.pillHoverSpringDamping),
            value: isHovering
        )
        .onHover { isHovering = $0 }
    }

    // MARK: - Shape (fill, border, shadow/glow)

    @ViewBuilder
    private var shape: some View {
        let fillColor = variant.dock.isNotch ? Theme.Brand.black : Theme.Semantic.pillBackground
        let borderColor = variant.theme == .dark ? Color.white.opacity(0.16) : Theme.Brand.deepNavy.opacity(0.08)

        Group {
            if variant.dock.isNotch {
                // §3: "Square top corners, 17 radius bottom corners."
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: cornerRadius,
                    bottomTrailingRadius: cornerRadius, topTrailingRadius: 0, style: .continuous
                )
                .fill(fillColor)
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0, bottomLeadingRadius: cornerRadius,
                        bottomTrailingRadius: cornerRadius, topTrailingRadius: 0, style: .continuous
                    )
                    .strokeBorder(isLowBattery ? Theme.Brand.orange : borderColor, lineWidth: isLowBattery ? 1.5 : 1)
                )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(isLowBattery ? Theme.Brand.orange : borderColor, lineWidth: isLowBattery ? 1.5 : 1)
                    )
            }
        }
        // Base resting shadow (§3): y10 blur24 spread-8, approximated — SwiftUI's .shadow has no
        // spread term, so "spread" is folded into radius/opacity rather than modeled exactly.
        .shadow(
            color: (variant.theme == .dark ? Color.black : Theme.Brand.deepNavy).opacity(variant.theme == .dark ? 0.7 : 0.4),
            radius: 12, x: 0, y: 10
        )
        // Notch glow (§3): y12 blur26 spread-10, BrandOrange 60% — always present under the notch,
        // independent of battery level.
        .shadow(color: variant.dock.isNotch ? Theme.Brand.orange.opacity(0.6) : .clear, radius: 13, x: 0, y: 12)
        // Low-battery glow (§3): blur22, 80%. Stacks with the notch glow above if both apply at
        // once — the guide doesn't address that combination explicitly.
        .shadow(color: isLowBattery ? Theme.Brand.orange.opacity(0.8) : .clear, radius: 11, x: 0, y: 0)
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if variant.photo == .noDevice {
            markView(dotOpacity: 0.4)
        } else if isVertical {
            VStack(spacing: 4) { primaryVisual; batteryIndicator }
        } else {
            HStack(spacing: 5) { primaryVisual; batteryIndicator }
        }
    }

    @ViewBuilder
    private var primaryVisual: some View {
        switch variant.photo {
        case .device(let assetName):
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: isVertical ? 22 : 26)
                .opacity(variant.photoOpacity)
                .saturation(variant.photoOpacity < 1 ? 0 : 1) // connecting: desaturated, not just faded
        case .genericMark, .noDevice:
            markView(dotOpacity: 1)
        }
    }

    private func markView(dotOpacity: Double) -> some View {
        let markSize: CGFloat = 20
        return ZStack {
            Image("HushArchTemplate")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(variant.theme == .dark ? .white : Theme.Brand.navy)
            // design/DESIGN_GUIDE.md §7: dot centred at (16, 20.5) on a 32 grid, radius 3.7.
            Circle()
                .fill(Theme.Brand.orange)
                .frame(width: markSize * (7.4 / 32), height: markSize * (7.4 / 32))
                .offset(y: markSize * ((20.5 - 16) / 32))
                .opacity(dotOpacity)
        }
        .frame(width: markSize, height: markSize)
    }

    // MARK: - Battery indicator

    @ViewBuilder
    private var batteryIndicator: some View {
        switch variant.battery {
        case .none:
            EmptyView()
        case .spinner:
            spinnerView
        case .bar(let percent, let isLow):
            barView(percent: percent, isLow: isLow)
        }
    }

    private var spinnerView: some View {
        ZStack {
            Circle().stroke(Theme.Brand.orange.opacity(0.25), lineWidth: 1.7)
            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(Theme.Brand.orange, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                .rotationEffect(.degrees(spinnerRotation))
        }
        .frame(width: 10, height: 10)
        .onAppear {
            withAnimation(
                .linear(duration: MotionConstants.connectingSpinnerRevolution).repeatForever(autoreverses: false)
            ) { spinnerRotation = 360 }
        }
    }

    private func barView(percent: Int, isLow: Bool) -> some View {
        let fraction = max(0, min(1, Double(percent) / 100))
        let trackSize: CGSize = isVertical ? CGSize(width: 16, height: 3) : CGSize(width: 3, height: 14)

        return ZStack(alignment: isVertical ? .leading : .bottom) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.35)) // track: "grey at 35%"
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.Brand.orange)
                .frame(
                    width: isVertical ? trackSize.width * fraction : trackSize.width,
                    height: isVertical ? trackSize.height : trackSize.height * fraction
                )
        }
        .frame(width: trackSize.width, height: trackSize.height)
        // §9.4: "Low battery pill bar | Opacity 0.3 to 1, 1.2 s cycle, forever." §9.6: not in the
        // list of loops exempted from Reduce Motion (only the pending ring fill and the connecting
        // spinner are), so it stays fully opaque and still rather than pulsing there.
        .opacity(isLow && !reduceMotion ? (lowBatteryPulse ? 1 : 0.3) : 1)
        .onAppear {
            guard isLow, !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: MotionConstants.lowBatteryPillBarHalfCycle).repeatForever(autoreverses: true)
            ) { lowBatteryPulse = true }
        }
    }
}

// MARK: - Previews (design/DESIGN_GUIDE.md §3; design/reference/15-16, 17-pill-closeup-*)

#Preview("770NC - Dark") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 82, theme: .dark, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("770NC - Light") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 82, theme: .light, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.white)
}

#Preview("670NC - Dark") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune670Black", white: "Tune670White")),
        connection: .connected, batteryPercent: 64, theme: .dark, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("670NC - Light") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune670Black", white: "Tune670White")),
        connection: .connected, batteryPercent: 64, theme: .light, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.white)
}

#Preview("Connecting - Dark") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connecting, batteryPercent: nil, theme: .dark, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("Connecting - Light") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connecting, batteryPercent: nil, theme: .light, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.white)
}

#Preview("Low Battery - Dark") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 9, theme: .dark, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("Low Battery - Light") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 9, theme: .light, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.white)
}

#Preview("No Device - Dark") {
    CollapsedPill(variant: .resolve(
        device: .noDevice, connection: .connected, batteryPercent: nil, theme: .dark, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("No Device - Light") {
    CollapsedPill(variant: .resolve(
        device: .noDevice, connection: .connected, batteryPercent: nil, theme: .light, dock: .top(isNotched: false)
    ))
    .padding(40)
    .background(Color.white)
}

#Preview("Side Dock - Dark") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 82, theme: .dark, dock: .left
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("Side Dock - Light") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 82, theme: .light, dock: .right
    ))
    .padding(40)
    .background(Color.white)
}

#Preview("Bottom Dock - Dark") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 82, theme: .dark, dock: .bottom
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("Bottom Dock - Light") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 82, theme: .light, dock: .bottom
    ))
    .padding(40)
    .background(Color.white)
}

#Preview("Notch") {
    CollapsedPill(variant: .resolve(
        device: .matched(photo: HeadphonePhotoAssetNames(black: "Tune770Black", white: "Tune770White")),
        connection: .connected, batteryPercent: 82, theme: .light, dock: .top(isNotched: true)
    ))
    .padding(40)
    .background(Color.black)
}
