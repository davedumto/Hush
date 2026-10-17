import CoreGraphics

/// Builds the island's silhouette as a single rounded-rectangle family, so a resize can morph
/// continuously between "small floating pill" and "wide flush card" instead of jumping between
/// two different shape builders.
/// `inset` floats the shape inward from the frame edges (the capsule's "floating in the menu
/// bar" look; 0 = flush/attached — the notch style, and always the expanded card).
/// `cornerRadius` ranges from a full pill (`pillRadius`, the collapsed capsule) down to a modest
/// card radius (`cardRadius`) — NotchSilhouetteView interpolates both smoothly across a resize.
enum IslandShape {
    static func path(size: CGSize, inset: CGFloat, cornerRadius: CGFloat) -> CGPath {
        let rect = CGRect(
            x: inset, y: inset,
            width: max(0, size.width - inset * 2), height: max(0, size.height - inset * 2)
        )
        let radius = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The modest corner radius a card uses (the expanded state, or a flush/notch-style
    /// collapsed shape) — never a full pill, regardless of how wide the card is. Must match
    /// ExpandedCard's own `cornerRadius: 33` exactly, not just approximately: this is the native
    /// backdrop drawn *underneath* that SwiftUI shape, and any smaller radius here leaves its own
    /// flatter corner sticking out past the SwiftUI card's tighter curve — visible as the
    /// backdrop's fill color (and, with the card's own border restored, the orange border sitting
    /// "inside" a visible sliver of it) right at the corners.
    static func cardRadius(height: CGFloat) -> CGFloat {
        min(33, height * 0.34)
    }

    /// The full-pill radius a floating capsule uses at rest.
    static func pillRadius(height: CGFloat) -> CGFloat {
        height / 2
    }
}
