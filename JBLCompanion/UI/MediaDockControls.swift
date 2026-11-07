import SwiftUI

/// Play/pause/next/previous for the now-playing media dock (ExpandedCard.heroSection, swapped in
/// place of the headphone photo — see NowPlayingDockView's own doc comment, including its history
/// of owner feedback on this exact file). Three identical bare glyphs, no fill or stroke on any of
/// them, including play/pause — the reference image has zero background chrome on any control, and
/// the owner was explicit after two rounds of this view still adding some ("look at this image very
/// closely"). A dedicated small view rather than reusing ModeButtonsSection: that view is
/// structurally built around 4 fixed noise-mode buttons with fixed icons/labels, not a fit for
/// transport controls.
struct MediaDockControls: View {
    let isPlaying: Bool
    let onCommand: (NowPlayingCommand) -> Void

    var body: some View {
        HStack(spacing: 26) {
            glyphButton(systemImage: "backward.fill", size: 16) { onCommand(.previous) }
            glyphButton(systemImage: isPlaying ? "pause.fill" : "play.fill", size: 19) { onCommand(.togglePlayPause) }
            glyphButton(systemImage: "forward.fill", size: 16) { onCommand(.next) }
        }
    }

    private func glyphButton(systemImage: String, size: CGFloat, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.Semantic.textPrimary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Media dock controls - Dark") {
    VStack(spacing: 20) {
        MediaDockControls(isPlaying: true, onCommand: { _ in })
        MediaDockControls(isPlaying: false, onCommand: { _ in })
    }
    .padding(40)
    .background(Color.black)
}

#Preview("Media dock controls - Light") {
    VStack(spacing: 20) {
        MediaDockControls(isPlaying: true, onCommand: { _ in })
        MediaDockControls(isPlaying: false, onCommand: { _ in })
    }
    .padding(40)
    .background(Color.white)
}
