import SwiftUI

/// The equalizer's own on/off toggle + curve + 6-preset grid, with no window chrome of its own —
/// embedded in ExpandedCard's own in-tray settings sheet (owner request, 2026-10-22: "I do not
/// want to be opening all those windows" — this used to be its own separate Window, now it's a
/// sheet reached through the card's gear icon, same as Island Settings). Mirrors the real JBL
/// app's own layout (curve up top, 2x3 preset grid below, on/off toggle in the header) but in
/// Hush's own card styling — panel gradient, glass rows, BrandOrange accents — not a copy of their
/// flat white UI. EqualizerPreset's own doc comment covers what's hardware-verified here and what
/// isn't.
struct EqualizerControls: View {
    let canUseEqualizer: Bool
    let equalizerPreset: EqualizerPreset?
    let equalizerOn: Bool
    let onSelectPreset: (EqualizerPreset) -> Void
    let onSetOn: (Bool) -> Void

    /// Owner-reported: switching presets just snapped the curve to its new shape, which "looks
    /// weird." This traces it left-to-right instead — `.trim` reveals however much of the
    /// (already-updated-to-the-new-preset) path is drawn, reset to 0 and animated back to 1 on
    /// every preset change, so the line reads as traveling the visualization path rather than
    /// teleporting.
    @State private var curveTrimEnd: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if canUseEqualizer {
                curve
                presetGrid
            } else {
                unavailableNotice
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Equalizer")
                .font(.custom("Fredoka-SemiBold", size: 19))
                .foregroundStyle(Theme.Semantic.textPrimary)
            Spacer()
            if canUseEqualizer {
                OrangeToggle(isOn: Binding(get: { equalizerOn }, set: { onSetOn($0) }))
            }
        }
    }

    private var unavailableNotice: some View {
        Text("Equalizer controls aren't verified for this model yet.")
            .font(Theme.Fonts.subText)
            .foregroundStyle(Theme.Semantic.textSecondary)
    }

    /// Frequency axis under the curve — owner-reported, matches the real JBL app's own graph
    /// (32/64/125/250/500/1k/2k/4k/8k/16k), purely a visual reference label row like
    /// `EqualizerCurveShape`'s own doc comment: not decoded from the real gain-curve bytes, just
    /// the standard octave-band ticks a frequency-response graph always shows.
    private static let frequencyLabels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    private var curve: some View {
        let preset = equalizerPreset ?? .studio
        return VStack(spacing: 6) {
            ZStack {
                // Dashed vertical gridline per frequency tick, one per `frequencyLabels` column —
                // owner-reported missing against the real JBL app's own graph reference.
                EqualizerGridShape(columnCount: Self.frequencyLabels.count)
                    .stroke(Theme.Semantic.glassStroke, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                EqualizerCurveShape(points: preset.curvePoints)
                    .trim(from: 0, to: curveTrimEnd)
                    .stroke(Theme.Brand.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if !equalizerOn {
                    Text("Off")
                        .font(Theme.Fonts.eyebrow)
                        .foregroundStyle(Theme.Semantic.textSecondary)
                }
            }
            .frame(height: 118)
            HStack(spacing: 0) {
                ForEach(Self.frequencyLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.Semantic.textSecondary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .opacity(equalizerOn ? 1 : 0.35)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(Theme.Semantic.glassFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.Semantic.glassStroke, lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: equalizerOn)
        .onChange(of: equalizerPreset) { _, _ in
            curveTrimEnd = 0
            withAnimation(.easeOut(duration: 0.55)) {
                curveTrimEnd = 1
            }
        }
    }

    private var presetGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(EqualizerPreset.allCases) { preset in
                presetButton(preset)
            }
        }
    }

    private func presetButton(_ preset: EqualizerPreset) -> some View {
        let isSelected = equalizerOn && equalizerPreset == preset
        return Button {
            onSelectPreset(preset)
        } label: {
            // Each word on its own line ("Extreme" / "Bass") rather than one wrapped line inside
            // the circle — owner-reported, matches the real JBL app's own two-line preset labels
            // and reads better in a fixed-diameter circle than letting SwiftUI wrap mid-word.
            VStack(spacing: 1) {
                ForEach(preset.displayName.split(separator: " ").map(String.init), id: \.self) { word in
                    Text(word)
                        .lineLimit(1)
                }
            }
            .font(Theme.Fonts.modeLabel())
            .multilineTextAlignment(.center)
            .foregroundStyle(isSelected ? Theme.Semantic.pillInk : Theme.Semantic.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isSelected ? AnyShapeStyle(Theme.Brand.orange) : AnyShapeStyle(Theme.Semantic.glassFill), in: Circle())
            .overlay(Circle().strokeBorder(isSelected ? Color.clear : Theme.Semantic.glassStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A smooth curve through a preset's own hand-placed control points (visual reference only — not
/// decoded from the real gain-curve bytes, which EqualizerPreset.transaction carries verbatim and
/// unparsed; this is purely illustrative, matching the general shape shown in the real JBL app's
/// own graph for each preset). Points are normalized 0...1 x (32Hz...16kHz) and -1...1 y (gain).
private struct EqualizerCurveShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        func resolve(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x * rect.width, y: (1 - (p.y + 1) / 2) * rect.height)
        }
        let resolved = points.map(resolve)
        path.move(to: resolved[0])
        for i in 1..<resolved.count {
            let previous = resolved[i - 1]
            let current = resolved[i]
            let midX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
        return path
    }
}

/// One dashed vertical line per frequency-label column, evenly spaced — the graph's own gridlines
/// (real JBL app reference), drawn behind `EqualizerCurveShape` in the same `ZStack`.
private struct EqualizerGridShape: Shape {
    let columnCount: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard columnCount > 1 else { return path }
        for i in 0..<columnCount {
            let x = rect.width * CGFloat(i) / CGFloat(columnCount - 1)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}

private extension EqualizerPreset {
    /// Hand-placed to match the real JBL app's own curve graph for each preset (visual reference
    /// only — see EqualizerCurveShape's own doc comment).
    var curvePoints: [CGPoint] {
        switch self {
        case .studio:
            return [
                CGPoint(x: 0.0, y: 0.15), CGPoint(x: 0.12, y: 0.35), CGPoint(x: 0.3, y: 0.1),
                CGPoint(x: 0.42, y: -0.35), CGPoint(x: 0.55, y: -0.05), CGPoint(x: 0.68, y: 0.1),
                CGPoint(x: 0.85, y: 0.25), CGPoint(x: 1.0, y: -0.05),
            ]
        case .bass:
            return [
                CGPoint(x: 0.0, y: 0.75), CGPoint(x: 0.15, y: 0.65), CGPoint(x: 0.3, y: 0.3),
                CGPoint(x: 0.42, y: -0.1), CGPoint(x: 0.55, y: -0.25), CGPoint(x: 0.7, y: -0.28),
                CGPoint(x: 0.85, y: -0.28), CGPoint(x: 1.0, y: -0.28),
            ]
        case .club:
            return [
                CGPoint(x: 0.0, y: 0.05), CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.35, y: -0.05),
                CGPoint(x: 0.5, y: -0.3), CGPoint(x: 0.65, y: -0.3), CGPoint(x: 0.78, y: 0.05),
                CGPoint(x: 0.9, y: 0.15), CGPoint(x: 1.0, y: 0.15),
            ]
        case .extremeBass:
            return [
                CGPoint(x: 0.0, y: 0.95), CGPoint(x: 0.12, y: 1.0), CGPoint(x: 0.28, y: 0.6),
                CGPoint(x: 0.45, y: -0.55), CGPoint(x: 0.55, y: -0.3), CGPoint(x: 0.68, y: 0.35),
                CGPoint(x: 0.78, y: 0.45), CGPoint(x: 0.9, y: 0.15), CGPoint(x: 1.0, y: -0.15),
            ]
        case .vocal:
            return [
                CGPoint(x: 0.0, y: -0.35), CGPoint(x: 0.15, y: -0.55), CGPoint(x: 0.3, y: -0.4),
                CGPoint(x: 0.42, y: 0.1), CGPoint(x: 0.55, y: 0.45), CGPoint(x: 0.68, y: 0.4),
                CGPoint(x: 0.85, y: 0.05), CGPoint(x: 1.0, y: -0.5),
            ]
        case .jazz:
            return [
                CGPoint(x: 0.0, y: 0.4), CGPoint(x: 0.15, y: 0.1), CGPoint(x: 0.3, y: 0.15),
                CGPoint(x: 0.45, y: -0.55), CGPoint(x: 0.6, y: -0.45), CGPoint(x: 0.73, y: 0.05),
                CGPoint(x: 0.87, y: 0.35), CGPoint(x: 1.0, y: 0.45),
            ]
        }
    }
}

#Preview("Equalizer – dark") {
    EqualizerCurvePreviewHarness()
        .padding(40)
        .background(Color.black)
        .preferredColorScheme(.dark)
}

/// A standalone preview of just the curve shapes (no AppDelegate dependency) — cycles through all
/// six so each preset's visual silhouette can be checked at a glance.
private struct EqualizerCurvePreviewHarness: View {
    var body: some View {
        VStack(spacing: 16) {
            ForEach(EqualizerPreset.allCases) { preset in
                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName).font(Theme.Fonts.eyebrow).foregroundStyle(.white.opacity(0.6))
                    EqualizerCurveShapePreviewOnly(points: preset.curvePoints)
                        .stroke(Theme.Brand.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(height: 60)
                }
            }
        }
    }
}

private struct EqualizerCurveShapePreviewOnly: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path { EqualizerCurveShape(points: points).path(in: rect) }
}
