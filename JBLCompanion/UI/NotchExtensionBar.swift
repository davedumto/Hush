import SwiftUI

/// Owner spec, 2026-10-24: the collapsed representation on a real notched display is no longer a
/// separate circular pill floating beside the notch (that read as a disconnected floating dot,
/// not part of the notch at all) — it's a fused extension of the notch itself: same black fill,
/// never taller than the notch, logo mark in the left wing, the current noise-mode icon in the
/// right wing. The physical camera cutout sits between the two wings; nothing needs to be drawn
/// there (and nothing *can* be — there are no pixels over a real camera housing), so this just
/// lays the two icons out at the view's own leading/trailing edges with a `Spacer()` soaking up
/// the middle, rather than needing to know the notch's exact width itself.
///
/// NotchPanel.collapsedSize(for:geometry:)/windowFrame(for:) size and position the window so this
/// view's own width already spans notch-width + a wing on each side — this view only owns what's
/// drawn inside that span, not where it sits on screen.
struct NotchExtensionBar: View {
    /// `NoiseMode`, not `CommandableNoiseMode` — this mirrors live headphone state
    /// (`HeadphoneState.noiseMode`), which includes `.unknown` (not yet connected/reported);
    /// `CommandableNoiseMode` is only the subset a user can actually request.
    let noiseMode: NoiseMode
    /// Owner spec, 2026-10-25: "when a media is playing, it shows a little [animation] on the
    /// side where the noise mode setting is to indicate that media is playing." Swaps the static
    /// noise-mode icon for an animated "waveform" SF Symbol while true — MediaPlaybackMonitor's
    /// own doc comment covers where this ultimately comes from (HeadphoneState.isMediaPlaying).
    let isMediaPlaying: Bool
    /// Owner spec, 2026-10-25: "when the headphone is connected, make the logo mark on the notch
    /// to be orange. and when disconnected, white." Tints the left-wing logo only — the
    /// noise-mode/media side on the right is unaffected.
    let isConnected: Bool
    let height: CGFloat
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    private var noiseModeIcon: some View {
        if isMediaPlaying {
            // Owner request, 2026-10-25 (round 3 — "this is what I wanted on the notch" too, after
            // seeing CollapsedPill's own version land): the same shared `AnimatedWaveformBars` now
            // used on Island mode's pill, instead of this bar's own SF-Symbol-based attempt — see
            // AnimatedWaveformBars's own doc comment for why an SF Symbol bounce/variable-value
            // effect (both tried and rejected here first) lost out to five hand-drawn, hand-animated
            // bars once Island mode needed its own version too.
            // `icon(_:)` below draws every other glyph in this bar at `height * 0.5` inside a
            // `height x height` layout slot — passing `AnimatedWaveformBars` the full `height`
            // instead made it render roughly 2x the size of every icon beside it (owner-reported,
            // 2026-10-25: "it looks shitty... adjust the size to be the size of what it was").
            // Matching that same 0.5 scale, then re-wrapping in the same `height x height` slot,
            // keeps this icon's on-screen size identical to what it replaced without disturbing
            // the HStack's own left/right wing layout.
            AnimatedWaveformBars(height: height * 0.5, tint: .white)
                .frame(width: height, height: height)
        } else {
            switch noiseMode {
            case .off: icon("IconOff")
            case .anc: icon("IconANC")
            case .ambientAware: icon("IconAmbient")
            case .talkThru: icon("IconTalkThru")
            // No device connected yet (or mode not reported) — a neutral system glyph rather than
            // implying a specific mode that isn't actually active.
            case .unknown: systemIcon("waveform")
            }
        }
    }

    private static let bottomCornerRadius: CGFloat = 14
    /// Owner request, 2026-10-25 (round 2 — trying it out): rounding the top corners too, to see
    /// how it reads against the flush-top reasoning the bottom-only version above was built on.
    /// Smaller than `bottomCornerRadius` on purpose — a top radius this small still looks like it
    /// belongs to the real notch's own corner, not like the bar has come loose from it.
    private static let topCornerRadius: CGFloat = 12

    private static var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topCornerRadius, bottomLeadingRadius: bottomCornerRadius,
            bottomTrailingRadius: bottomCornerRadius, topTrailingRadius: topCornerRadius
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            icon("HushMarkWhite", tint: isConnected ? Theme.Brand.orange : .white)
            Spacer(minLength: 0)
            noiseModeIcon
        }
        .frame(height: height)
        .background(Self.shape.fill(Theme.Brand.black))
        // Owner request, 2026-10-24: "add the orange border so we can see the distinction"; owner
        // request, 2026-10-25 (round 2): top corners now rounded too (`topCornerRadius`'s own doc
        // comment), so the border goes back to all four sides, matching the shape it now outlines
        // — same BrandOrange CollapsedPill/ExpandedCard already use everywhere else, so this fused
        // bar reads as unmistakably part of Hush rather than blending into the real notch/menu bar.
        .overlay(Self.shape.stroke(Theme.Brand.orange.opacity(0.9), lineWidth: 1.5))
        // Owner request, 2026-10-25: "a little swell animation on hover" — same spring
        // CollapsedPill's own hover scale already uses elsewhere (MotionConstants.pillHoverScale/
        // pillHoverSpringResponse/pillHoverSpringDamping), so hover feels consistent across both
        // collapsed representations. Anchored to `.top`, not centered: the bar is flush against
        // the real screen edge, so scaling from center would push it past that edge — growing
        // down/outward from the top instead keeps the flush edge flush while it swells.
        .scaleEffect(isHovering ? MotionConstants.pillHoverScale : 1, anchor: .top)
        .animation(
            reduceMotion ? nil : .spring(response: MotionConstants.pillHoverSpringResponse, dampingFraction: MotionConstants.pillHoverSpringDamping),
            value: isHovering
        )
        .onHover { isHovering = $0 }
    }

    private func icon(_ assetName: String, tint: Color = .white) -> some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(tint)
            .frame(width: height * 0.5, height: height * 0.5)
            .frame(width: height, height: height)
    }

    private func systemIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .frame(width: height * 0.5, height: height * 0.5)
            .frame(width: height, height: height)
    }
}

#Preview("Notch extension bar") {
    NotchExtensionBar(noiseMode: .anc, isMediaPlaying: false, isConnected: true, height: 33)
        .frame(width: 33 + 64, height: 33)
        .padding(40)
        .background(Color.gray)
}

#Preview("Notch extension bar — media playing") {
    NotchExtensionBar(noiseMode: .anc, isMediaPlaying: true, isConnected: true, height: 33)
        .frame(width: 33 + 64, height: 33)
        .padding(40)
        .background(Color.gray)
}
