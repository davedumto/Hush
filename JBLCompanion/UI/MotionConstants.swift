import CoreGraphics
import SwiftUI

/// Single source of truth for design/DESIGN_GUIDE.md §9's timing values (expand/collapse spring,
/// content stagger, Reduce Motion crossfade, small loops) — CLAUDE.md's engineering preference:
/// "Keep timing values in one constants file," so no animation literal lives scattered across
/// NotchView/ExpandedCard/CollapsedPill/NotchPanel/CardConditionViews.
///
/// Split into two halves, the same way DockPlacement.swift splits pure geometry from NotchView's
/// own view-layer bridge: a framework-light, pure/testable half (durations, delays, and the
/// `CardTransitionKind`/`WindowResizeOrdering` selection logic XCTest can assert on directly) and
/// a thin SwiftUI `Animation` adapter at the bottom that views actually call — `Animation` itself
/// has no meaningful Equatable conformance to assert against, so the selection *decision* lives in
/// plain enums instead, and only the final "turn that into a real Animation" step touches SwiftUI.
enum MotionConstants {
    // MARK: - §9.1/9.2 Expand/collapse card transition

    /// §9.1 point 3: "response 0.42, damping 0.78 — about 460 ms with a small overshoot of about 3%."
    static let expandSpringResponse: Double = 0.42
    static let expandSpringDamping: Double = 0.78
    /// §9.2 point 2: "critically damped spring (response 0.28, damping 1.0) — about 280 ms, no overshoot."
    static let collapseSpringResponse: Double = 0.28
    static let collapseSpringDamping: Double = 1.0
    /// §9.6: "Expand, collapse and mode changes become a 160 ms ease in out crossfade" under Reduce Motion.
    static let reducedMotionCrossfadeDuration: Double = 0.16

    /// §9.1 point 4 / §9.2 point 3: the pill scales to/from this while the card takes over.
    static let pillTransitionScale: CGFloat = 0.5
    /// §9.1 point 2: the card itself starts/ends its own scale transition here.
    static let cardTransitionScale: CGFloat = 0.1
    /// §9.1 point 2: "goes from blur 10 to blur 0."
    static let cardTransitionBlurRadius: CGFloat = 10

    // MARK: - §9.1 point 6: content stagger

    /// Which block of ExpandedCard's content a stagger-in modifier is attached to — only used to
    /// key into `staggerDelay(for:)` below, never stored on the view itself.
    enum ContentBlock: CaseIterable {
        case topRow, hero, name, controls
    }

    /// §9.1 point 6's own delay table, "from the start of the expand": top row 80 ms, hero 110 ms,
    /// name 140 ms, controls 170 ms. "Same order on the left and right docks" — this table doesn't
    /// branch on dock, deliberately.
    static func staggerDelay(for block: ContentBlock) -> Double {
        switch block {
        case .topRow: return 0.08
        case .hero: return 0.11
        case .name: return 0.14
        case .controls: return 0.17
        }
    }

    /// §9.6: "No stagger" at all under Reduce Motion — every block appears together, un-delayed,
    /// as part of the plain crossfade.
    static func staggerDelay(for block: ContentBlock, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : staggerDelay(for: block)
    }

    /// §9.1 point 6: "each block fades in and rises 6 pt, ease out 260 ms."
    static let staggerRiseDistance: CGFloat = 6
    static let staggerDuration: Double = 0.26

    // MARK: - §9.4 Small loops

    /// Already built exactly to spec in CollapsedPill — kept here too so it's the one place every
    /// loop's timing lives, not duplicated as a second hardcoded literal.
    static let pillHoverSpringResponse: Double = 0.32
    static let pillHoverSpringDamping: Double = 0.6
    static let pillHoverScale: CGFloat = 1.06

    /// Half-cycle durations: `.easeInOut(duration:).repeatForever(autoreverses: true)` runs each
    /// half once per direction, so the *full* cycle the guide states is always double this.
    static let pulsingStatusDotHalfCycle: Double = 0.55 // §9.4: "1.1 s full cycle."
    static let connectingSpinnerRevolution: Double = 0.8 // §9.4: "every 0.8 s" (one-way, not a half-cycle).
    static let skeletonShimmerHalfCycle: Double = 0.75 // §9.4: "0.75 s" substitute, already one-way per the guide's own wording.
    static let lowBatteryPillBarHalfCycle: Double = 0.6 // §9.4: "1.2 s cycle."
    static let lowBatteryChipGlowHalfCycle: Double = 0.9 // §9.4: "1.8 s, forever."
    /// §9.4 "Low battery chip": "Orange glow ring expands from 0 to 8 pt while fading from 50% to 0%."
    static let lowBatteryChipGlowMaxRadius: CGFloat = 8
    static let lowBatteryChipGlowMaxOpacity: Double = 0.5

    // MARK: - Pure, testable selection logic

    /// What kind of card transition applies — Reduce Motion collapses every dimension (scale,
    /// blur, overshoot, stagger) down to a plain crossfade (§9.6); otherwise the real spring from
    /// §9.1/9.2 applies.
    enum CardTransitionKind: Equatable {
        case spring(response: Double, dampingFraction: Double)
        case crossfade(duration: Double)
    }

    static func expandTransitionKind(reduceMotion: Bool) -> CardTransitionKind {
        reduceMotion
            ? .crossfade(duration: reducedMotionCrossfadeDuration)
            : .spring(response: expandSpringResponse, dampingFraction: expandSpringDamping)
    }

    static func collapseTransitionKind(reduceMotion: Bool) -> CardTransitionKind {
        reduceMotion
            ? .crossfade(duration: reducedMotionCrossfadeDuration)
            : .spring(response: collapseSpringResponse, dampingFraction: collapseSpringDamping)
    }

    /// design/DESIGN_GUIDE.md §9.1 point 1 / §9.2 point 4: "window first" on the way in, "window
    /// last" on the way out — the panel's own NSPanel frame (and, in this app, the hosting content
    /// frame that grows/shrinks alongside it) always grows to the envelope size *before* the
    /// visible animation starts, and only shrinks back down *after* it finishes, regardless of
    /// direction. A pure enum, mirroring DockPlacement.EdgeChangeStep, so NotchPanel.present()'s
    /// own sequencing is an explicit, testable decision rather than something only provable by
    /// reading the procedural code around it.
    enum WindowResizeOrdering: Equatable {
        case growBeforeAnimating
        case shrinkAfterAnimating
    }

    static func windowResizeOrdering(forExpanding expanding: Bool) -> WindowResizeOrdering {
        expanding ? .growBeforeAnimating : .shrinkAfterAnimating
    }
}

// MARK: - SwiftUI adapter (not unit-testable — Animation has no meaningful Equatable conformance)

extension MotionConstants.CardTransitionKind {
    var animation: Animation {
        switch self {
        case .spring(let response, let dampingFraction):
            return .spring(response: response, dampingFraction: dampingFraction)
        case .crossfade(let duration):
            return .easeInOut(duration: duration)
        }
    }
}

/// §9.1 point 2 / §9.2 point 2: "goes from blur 10 to blur 0" on the way in, and symmetrically
/// blurs on the way out — `.modifier(active:identity:)` applies to both insertion and removal.
private struct BlurTransitionModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    static var cardBlurIn: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(radius: MotionConstants.cardTransitionBlurRadius),
            identity: BlurTransitionModifier(radius: 0)
        )
    }
}

/// §9.1 point 5 "Photo flight": the headphone photo in CollapsedPill and the hero photo in
/// ExpandedCard share this one id/namespace so `matchedGeometryEffect` flies/grows the small photo
/// into the big one, instead of one fading out while the other fades in separately. Shared here
/// (not duplicated in both views) since both need the exact same id. A `nil` namespace — every
/// preview/caller that isn't NotchView itself, and any call under Reduce Motion (§9.6: "No photo
/// flight") — renders `content` unchanged, a plain crossfade between two independent images.
struct PhotoFlight: ViewModifier {
    static let id = "headphonesPhoto"
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: Self.id, in: namespace)
        } else {
            content
        }
    }
}
