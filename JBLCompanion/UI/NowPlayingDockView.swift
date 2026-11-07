import SwiftUI

/// The now-playing media dock's own content — swapped into ExpandedCard.heroSection in place of the
/// headphone photo while the dock is open (that view's own doc comment).
///
/// Owner feedback history, 2026-11-07, in order: (1) first build (artwork/text/controls floating
/// loose, a small waveform beside the title) — "does not look like... the glassmorphism vibe";
/// (2) a bordered `.ultraThinMaterial` card — "looks sooo clogged up... not the apple vibe";
/// (3) borderless material + shadow — still rejected, a car-HUD reference re-sent with "look very
/// closely"; (4) card removed, glow pushed way up — still wrong, plus a macOS Control Center
/// screenshot: "this is how i want the media background to look... research and implement it";
/// (5) a plain solid `Theme.Semantic.glassFill` card approximating Control Center's own module look
/// — "mehn this is not the feel i want, can you do research on the apple background glass effect?
/// check online!!!!!" Researched for real this time, not guessed: macOS 26 (the owner's own OS)
/// ships an actual native Liquid Glass API — `View.glassEffect(_:in:)` — and macOS Tahoe's redesigned
/// Control Center (the reference screenshot) is confirmed to use exactly this, not a hand-built
/// imitation. Apple's own usage examples never add a stroke or shadow on top of it — the material
/// supplies the lensing/elevation look by itself, which is exactly the ingredient every prior manual
/// attempt here was missing. `NowPlayingGlassBackground` below applies the real modifier, gated by
/// `#available(macOS 26.0, *)` rather than raising this project's deployment target — that's a
/// product-wide compatibility decision (this app has a real shipped release with Sparkle
/// auto-update now, unlike when the deployment target was last raised pre-release) outside what a
/// single UI fix should silently decide; anyone on an older macOS falls back to the same solid-color
/// approximation attempt (5) used. The artwork's own glow (attempt (4)'s overshoot, dialed back) is
/// kept as a secondary accent alongside the real glass card, not a replacement for it.
///
/// Pure function of its inputs, same as every other hero element — all the data behind it lives on
/// HeadphoneState's nowPlaying* fields.
struct NowPlayingDockView: View {
    let title: String?
    let artist: String?
    let artwork: NSImage?
    let sourceAppIcon: NSImage?
    let isPlaying: Bool
    let durationSeconds: TimeInterval?
    let elapsedSeconds: TimeInterval?
    let elapsedSnapshotDate: Date?
    /// ExpandedCard's own `isVertical` — the dock has to fit inside `heroHeight`, which is shorter
    /// on side docks (196pt vs 236pt), so artwork size scales down to match rather than overflowing.
    let isVertical: Bool
    let onCommand: (NowPlayingCommand) -> Void

    private var artworkSize: CGFloat { isVertical ? 60 : 80 }
    private var contentWidth: CGFloat { isVertical ? 150 : 190 }
    private var cardPadding: CGFloat { isVertical ? 7 : 9 }

    var body: some View {
        // Owner correction, 2026-11-07: not a rework of the open/close animation — a fix to the
        // glass effect itself. Real Liquid Glass blurs/refracts whatever sits BEHIND it; that's
        // what makes Control Center's own glass look convincing, since it's sampling actual varied
        // desktop content. The artwork glow used to live *inside* `artworkView`, itself a child of
        // the glass-wrapped VStack — rendered ON the glass, not behind it, so the glass had nothing
        // but this app's own flat navy panel to sample and read as a plain tint instead of real
        // glass. Moved here, behind the whole glass-wrapped block in a ZStack, so the glass surface
        // actually has rich, color-matched content underneath it to refract.
        ZStack {
            backgroundGlow
            cardContent
        }
    }

    @ViewBuilder
    private var backgroundGlow: some View {
        // Owner-reported: `.frame(maxWidth: .infinity)` here made this the ZStack's own largest
        // child, which made the *whole* NowPlayingDockView report that width as its outer frame —
        // and ExpandedCard's `.overlay(alignment: .topTrailing)` for the close button anchors to
        // exactly that outer frame, so the button landed at the edge of this invisible oversized
        // box instead of the visible card's own corner. A fixed size lets the ZStack's real size be
        // dictated by `cardContent` (the actual visible card) as intended, with this just centering
        // within whatever that resolves to.
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: artworkSize * 1.8, height: artworkSize * 1.8)
                .blur(radius: artworkSize * 0.5)
                .opacity(0.55)
                .offset(y: -(artworkSize * 0.25))
        }
    }

    private var cardContent: some View {
        VStack(spacing: isVertical ? 6 : 8) {
            artworkView
            if title != nil || artist != nil {
                VStack(spacing: 2) {
                    if let title {
                        Text(title)
                            .font(Theme.Fonts.deviceName)
                            .foregroundStyle(Theme.Semantic.textPrimary)
                            .lineLimit(1)
                    }
                    if let artist {
                        Text(artist)
                            .font(Theme.Fonts.subText)
                            .foregroundStyle(Theme.Semantic.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: contentWidth)
            } else {
                Text("Nothing playing")
                    .font(Theme.Fonts.subText)
                    .foregroundStyle(Theme.Semantic.textSecondary)
            }
            if let durationSeconds, durationSeconds > 0 {
                NowPlayingProgressBar(
                    duration: durationSeconds, elapsedAtSnapshot: elapsedSeconds ?? 0,
                    snapshotDate: elapsedSnapshotDate ?? Date(), isPlaying: isPlaying, width: contentWidth
                )
            }
            MediaDockControls(isPlaying: isPlaying, onCommand: onCommand)
        }
        .padding(.vertical, cardPadding)
        .padding(.horizontal, cardPadding + 8)
        .modifier(NowPlayingGlassBackground(cornerRadius: 20))
    }

    @ViewBuilder
    private var artworkView: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Theme.Semantic.glassFill
                        Image(systemName: "music.note")
                            .font(.system(size: artworkSize * 0.28, weight: .semibold))
                            .foregroundStyle(Theme.Semantic.textSecondary)
                    }
                }
            }
            .frame(width: artworkSize, height: artworkSize)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let sourceAppIcon {
                Image(nsImage: sourceAppIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .padding(3)
                    .background(Theme.Semantic.cardFrame, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .offset(x: 7, y: 7)
            }
        }
        .frame(width: artworkSize, height: artworkSize)
    }
}

/// The real Liquid Glass material (macOS 26) when available, falling back to a plain solid fill
/// otherwise — NowPlayingDockView's own doc comment on why this is gated by `#available` rather than
/// raising the project's deployment target. Apple's own examples never add a stroke or shadow on top
/// of `glassEffect` — the material supplies the lensing/elevation look by itself — so neither branch
/// adds one; the fallback is deliberately the same flat, chrome-free treatment this app already uses
/// everywhere else (`Theme.Semantic.glassFill`), not a hand-built imitation of the real effect.
/// Wrapped in `GlassEffectContainer` even for this one element — every one of Apple's own
/// `glassEffect` examples does, and research confirmed it's what's required for correct
/// rendering/performance, not just a multi-element nicety.
private struct NowPlayingGlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content.background(Theme.Semantic.glassFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Elapsed/remaining time + a filled track, matching the reference image's car-display layout
/// exactly: elapsed on the left, "-remaining" on the right. `TimelineView(.periodic)`, not a
/// repeating `Timer` — same reasoning as AnimatedWaveformBars' own doc comment (this app's custom
/// window-resize pipeline suppresses ordinary SwiftUI animation/state-driven re-renders), and it
/// extrapolates from `elapsedAtSnapshot`/`snapshotDate` by wall-clock time rather than needing a
/// fresh push from the adapter every second — MediaRemoteAdapter only pushes on actual state
/// changes (play/pause/track change/seek), not continuously.
private struct NowPlayingProgressBar: View {
    let duration: TimeInterval
    let elapsedAtSnapshot: TimeInterval
    let snapshotDate: Date
    let isPlaying: Bool
    let width: CGFloat

    var body: some View {
        // A long, fixed interval while paused — `.periodic` still needs a positive interval, and
        // the displayed position is frozen (not advancing) whenever `isPlaying` is false anyway, so
        // nothing meaningful would change between ticks.
        TimelineView(.periodic(from: snapshotDate, by: isPlaying ? 1 : 3600)) { context in
            let elapsed = isPlaying
                ? min(duration, max(0, elapsedAtSnapshot + context.date.timeIntervalSince(snapshotDate)))
                : min(duration, max(0, elapsedAtSnapshot))
            let fraction = duration > 0 ? elapsed / duration : 0

            VStack(spacing: 4) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.Semantic.glassFill)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.Brand.orange)
                        .frame(width: max(0, min(1, fraction)) * width)
                }
                .frame(width: width, height: 3)

                HStack {
                    Text(Self.formatted(elapsed))
                    Spacer()
                    Text("-\(Self.formatted(max(0, duration - elapsed)))")
                }
                .font(Theme.Fonts.eyebrow)
                .foregroundStyle(Theme.Semantic.textSecondary)
                .frame(width: width)
            }
        }
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview("Now playing dock - with artwork + progress") {
    NowPlayingDockView(
        title: "Raindance (feat. Tems)", artist: "Dave", artwork: nil, sourceAppIcon: nil,
        isPlaying: true, durationSeconds: 219, elapsedSeconds: 89, elapsedSnapshotDate: Date(),
        isVertical: false, onCommand: { _ in }
    )
    .padding(40)
    .background(Color.black)
}

#Preview("Now playing dock - no artwork, paused") {
    NowPlayingDockView(
        title: "Raindance (feat. Tems)", artist: "Dave", artwork: nil, sourceAppIcon: nil,
        isPlaying: false, durationSeconds: 219, elapsedSeconds: 89, elapsedSnapshotDate: Date(),
        isVertical: false, onCommand: { _ in }
    )
    .padding(40)
    .background(Color.black)
}

#Preview("Now playing dock - nothing playing") {
    NowPlayingDockView(
        title: nil, artist: nil, artwork: nil, sourceAppIcon: nil, isPlaying: false,
        durationSeconds: nil, elapsedSeconds: nil, elapsedSnapshotDate: nil, isVertical: false,
        onCommand: { _ in }
    )
    .padding(40)
    .background(Color.black)
}

#Preview("Now playing dock - vertical dock, light") {
    NowPlayingDockView(
        title: "Raindance (feat. Tems)", artist: "Dave", artwork: nil, sourceAppIcon: nil,
        isPlaying: true, durationSeconds: 219, elapsedSeconds: 89, elapsedSnapshotDate: Date(),
        isVertical: true, onCommand: { _ in }
    )
    .padding(40)
    .background(Color.white)
}
