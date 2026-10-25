import SwiftUI

/// Shared "fake" animated waveform used by both NotchExtensionBar (Notch mode) and CollapsedPill
/// (Island mode) as their media-playing indicator — owner spec, 2026-10-25: "imagine [this] on the
/// island where that headphone image will be... [and this] is what I wanted on the notch" too, so
/// one view now backs both rather than CollapsedPill keeping its own private copy.
///
/// Driven by `TimelineView(.animation)`, not `@State` + `withAnimation(...).repeatForever(...)` —
/// two earlier versions tried that (first with one shared `@State` array for all five bars, then
/// with a separate `@State` per bar) and neither ever visibly animated in the real app, only
/// working correctly in SwiftUI Previews. This app's NotchSilhouetteView drives its own
/// window-resize animations with raw CAKeyframeAnimation/CATransaction control (IslandMotion.swift's
/// own doc comment), and something in that pipeline appears to suppress ordinary SwiftUI implicit/
/// explicit animation transactions within this window's view tree — `TimelineView(.animation)`
/// sidesteps that entirely by recomputing each bar's height straight from elapsed wall-clock time
/// on every frame, with no animation-transaction object involved at all.
struct AnimatedWaveformBars: View {
    let height: CGFloat
    /// The bar's "empty" color, same as what the view it replaces would have used (white in
    /// NotchExtensionBar, white/navy depending on theme in CollapsedPill).
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Owner-reported, 2026-10-25: "the notch comes into the screen on collapse... even the island
    /// icon is doing it." Root cause: NotchView hides the entire collapsed pill behind
    /// `.opacity(isPillVisible ? 1 : 0)` for the whole collapse swing, then snaps straight to
    /// opacity 1 with no fade the instant it settles (`isPillVisible`'s own doc comment) — harmless
    /// for a static photo/mark, but this view used to drive bar phase straight off
    /// `context.date.timeIntervalSinceReferenceDate` (absolute wall-clock time), so its first
    /// visible frame landed at whatever arbitrary mid-oscillation phase the wall clock already
    /// implied, instead of the calm phase `phases`/`restingFractions` were actually tuned around —
    /// reading as the icon's own content visibly jumping/snapping into place. Captured once per
    /// mount (View structs re-init on every parent render, but a `@State` initial-value closure
    /// only runs once per identity — exactly the "reset every time this (re)appears" behavior
    /// wanted here), so elapsed time always starts at 0 on the frame this view first appears.
    @State private var startTime = Date().timeIntervalSinceReferenceDate

    /// A short-tall-tallest-tall-short silhouette, the same shape the "waveform" SF Symbol reads
    /// as at rest — this is what makes it recognizable as a waveform rather than five random bars.
    private static let restingFractions: [CGFloat] = [0.35, 0.65, 1.0, 0.65, 0.35]
    /// Each bar's own phase (radians) and period (seconds) — deliberately uncorrelated so the five
    /// waves drift in and out of sync with each other forever rather than pulsing in lockstep,
    /// which is what actually reads as "waveform" rather than "blinking icon." Owner request,
    /// 2026-10-25: "slow down the animation a bit" — periods scaled up ~1.6x from the first
    /// working version.
    private static let phases: [Double] = [0, 1.1, 2.3, 0.6, 1.8]
    private static let periods: [Double] = [1.45, 1.1, 1.75, 1.3, 1.6]
    /// Bar width/gap as a fraction of `height`, sized so 5 bars + 4 gaps sum to well under 1.0 —
    /// an earlier, narrower version summed past 1.0 and overflowed the `.frame(width: height)` box
    /// this sits in (HStack doesn't clip to a parent frame that's smaller than its content), which
    /// read as visually overflowing/not pixel perfect. Owner request, 2026-10-25: "stretch the
    /// width a bit" (applied, 0.09/0.065 → 0.12/0.08) then explicitly "do not increase" it further
    /// on the next round — 0.12/0.08 is therefore final, not provisional.
    private static let barWidthFraction: CGFloat = 0.12
    private static let barSpacingFraction: CGFloat = 0.08

    var body: some View {
        if reduceMotion {
            bars(fractions: Self.restingFractions)
        } else {
            TimelineView(.animation) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate - startTime
                let fractions = Self.phases.indices.map { index -> CGFloat in
                    let angle = (elapsed / Self.periods[index]) * 2 * .pi + Self.phases[index]
                    // 0.3...1.0 — oscillates continuously but never bottoms out at a flat line, so
                    // it always visibly reads as "alive," never as a paused static icon.
                    return 0.3 + 0.7 * CGFloat((sin(angle) + 1) / 2)
                }
                bars(fractions: fractions)
            }
        }
    }

    private func bars(fractions: [CGFloat]) -> some View {
        // `.center`, same as the first confirmed-working version — owner request, 2026-10-25:
        // "let it be the last animation... you changed the animation style" after a `.bottom`-
        // aligned attempt (meant only to fix the straight-line artifact below) ended up reading as
        // a different motion entirely (bars rising from a shared floor, not bouncing from center).
        HStack(alignment: .center, spacing: height * Self.barSpacingFraction) {
            ForEach(fractions.indices, id: \.self) { index in
                Capsule()
                    .fill(barColor(for: index))
                    .frame(width: height * Self.barWidthFraction, height: max(height * 0.18, height * fractions[index]))
            }
        }
        .frame(width: height, height: height)
    }

    /// Owner request, 2026-10-25: "add some orange color to like half of the bars... like it is
    /// half full." The first attempt split every bar in half vertically with a gradient, which —
    /// combined with `.center` alignment above putting every bar's own split at the same absolute
    /// height — read as one continuous straight line cutting across the whole group rather than
    /// five separate bars (owner: "it is just a straight line"). Whole bars alternating solid
    /// tint/orange sidesteps that entirely: there's no split within any single bar for anything to
    /// line up into a line, while still reading as "half the bars are orange" at a glance.
    private func barColor(for index: Int) -> Color {
        index.isMultiple(of: 2) ? tint : Theme.Brand.orange
    }
}

#Preview("Waveform bars - Dark") {
    AnimatedWaveformBars(height: 40, tint: .white)
        .padding(40)
        .background(Color.black)
}

#Preview("Waveform bars - Light") {
    AnimatedWaveformBars(height: 40, tint: Theme.Brand.navy)
        .padding(40)
        .background(Color.white)
}
