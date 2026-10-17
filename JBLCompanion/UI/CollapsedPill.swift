import SwiftUI

/// The collapsed pill shown when the card isn't expanded — a circle, deliberately deviating from
/// design/DESIGN_GUIDE.md §3's own elongated 46x34/34x46 pill (CLAUDE.md records this deviation).
/// Purely a function of `variant` (PillVariant.resolve) plus local hover state for the scale-up
/// spring; never branches on raw profile/connection/battery facts itself.
///
/// Renders at `diameter` (IslandSettings.pillDiameter, user-adjustable; the same on every edge)
/// regardless of whatever frame it's placed in — NotchView centers it inside `collapsedSize`,
/// which NotchPanel.collapsedSize(for:geometry:) keeps in exact lockstep with this same diameter
/// (the one exception, a real camera notch, hangs flush and sized to its own housing instead —
/// see that function's own doc comment). The pill's own shape/fill/border/shadow are self-drawn
/// (unlike NotchView's other content, which never draws its own background — see its doc
/// comment): the native NotchSilhouetteView underneath is a fixed, always-black fill with no
/// theme awareness, so it can't produce the light theme's white pill or the per-condition
/// border/glow on its own.
struct CollapsedPill: View {
    let variant: PillVariant
    /// User-adjustable (IslandSettings.pillDiameter) — defaults to the designed size so every
    /// preview/caller that doesn't pass one explicitly keeps rendering at today's exact size.
    var diameter: CGFloat = DockPlacement.collapsedPillDiameter
    /// §9.1 point 5 "Photo flight": shared with ExpandedCard's own hero photo by NotchView, the
    /// common ancestor that owns the `@Namespace` — see ExpandedCard.photoNamespace's own doc
    /// comment for why this defaults to `nil` everywhere except NotchView itself.
    var photoNamespace: Namespace.ID? = nil
    @State private var isHovering = false
    @State private var spinnerRotation: Double = 0
    @State private var lowBatteryPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGSize {
        CGSize(width: diameter, height: diameter)
    }
    /// Every inner content size below is expressed relative to the *designed* diameter (52) and
    /// scaled by this factor, so a bigger pill keeps today's exact proportions instead of a
    /// fixed-size icon/battery indicator looking lost inside a larger circle.
    private var scale: CGFloat { diameter / DockPlacement.collapsedPillDiameter }
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
        // Orange at every battery level now, not just low — low battery still reads as distinct
        // via full opacity and a thicker stroke rather than a different color entirely. Light
        // theme needs far more opacity than dark to read as the same color at all: the same 0.5
        // that's clearly orange against a near-black fill washed out to barely-there against the
        // light pill background and the owner reported it as not visible.
        let borderColor = Theme.Brand.orange.opacity(variant.theme == .dark ? 0.5 : 0.9)

        // A plain circle, the same for every dock including the notch-fused one — no more of §3's
        // "square top corners" distinction (that was specifically to read as flush with a
        // rectangular camera housing from above; a circle has no "top corners" to square off, and
        // deliberately isn't trying to trace the camera housing's own outline anymore).
        Circle()
            .fill(fillColor)
            .overlay(
                Circle().strokeBorder(isLowBattery ? Theme.Brand.orange : borderColor, lineWidth: isLowBattery ? 1.5 : 1)
            )
        // Base resting shadow (§3): y10 blur24 spread-8, approximated — SwiftUI's .shadow has no
        // spread term, so "spread" is folded into radius/opacity rather than modeled exactly.
        // Dark theme only, on owner request: against a dark desktop background the shadow just
        // read as an unwanted dark smudge around the pill; light theme's own reference (a soft
        // shadow under a white circle, same as any normal floating card) keeps it.
        .shadow(
            color: variant.theme == .dark ? .clear : Theme.Brand.deepNavy.opacity(0.4),
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
        } else {
            // One layout for every dock now that the pill itself is a circle with no long axis —
            // icon above the battery indicator, same as the old vertical-dock arrangement.
            VStack(spacing: 4 * scale) { primaryVisual; batteryIndicator }
        }
    }

    @ViewBuilder
    private var primaryVisual: some View {
        switch variant.photo {
        case .device(let assetName):
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 26 * scale)
                .opacity(variant.photoOpacity)
                .saturation(variant.photoOpacity < 1 ? 0 : 1) // connecting: desaturated, not just faded
                // §9.1 point 5: flies/grows into ExpandedCard's hero photo on expand — see that
                // view's own doc comment on `photoNamespace`. Skipped under Reduce Motion (§9.6).
                .modifier(PhotoFlight(namespace: reduceMotion ? nil : photoNamespace))
        case .genericMark, .noDevice:
            markView(dotOpacity: 1)
        }
    }

    private func markView(dotOpacity: Double) -> some View {
        let markSize: CGFloat = 20 * scale
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
        .frame(width: 10 * scale, height: 10 * scale)
        .onAppear {
            withAnimation(
                .linear(duration: MotionConstants.connectingSpinnerRevolution).repeatForever(autoreverses: false)
            ) { spinnerRotation = 360 }
        }
    }

    private func barView(percent: Int, isLow: Bool) -> some View {
        let fraction = max(0, min(1, Double(percent) / 100))
        // One horizontal track for every dock, under the icon in the VStack above — same reason
        // `contentView` dropped its own isVertical branch.
        let trackSize = CGSize(width: 22 * scale, height: 3 * scale)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.35)) // track: "grey at 35%"
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.Brand.orange)
                .frame(width: trackSize.width * fraction, height: trackSize.height)
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
