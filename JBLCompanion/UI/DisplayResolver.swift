import CoreGraphics

/// Pure, testable "which display should the island use" decision — separated out of
/// NotchPanel.resolveScreen() specifically so the fallback behavior (a saved display preference
/// that no longer corresponds to anything connected) is unit-testable without real NSScreen
/// objects, which aren't mockable directly.
enum DisplayResolver {
    struct Candidate: Equatable {
        let uuid: String?
        let frame: CGRect
    }

    enum Choice: Equatable {
        /// The saved (chosenUUID) preference matched a connected, usable display.
        case chosen(index: Int)
        /// No usable match for the saved preference (or none was saved) — fell back to the first
        /// connected display. Also returned when there's nothing connected to choose from at all,
        /// as a degenerate but still-defined case (callers fall further back to IslandGeometry's
        /// own .zero-screen handling in that situation).
        case fallback(index: Int?)
    }

    /// `candidates` should be in the same order `NSScreen.screens` reports them, so index 0 is
    /// "the first/primary screen." A candidate only counts as usable if its frame has positive
    /// width and height — a zero-size frame is what a degenerate/disconnected display read looks
    /// like, and is never worth presenting the island on even if its UUID happens to match.
    static func resolve(chosenUUID: String?, candidates: [Candidate]) -> Choice {
        if let chosenUUID,
           let index = candidates.firstIndex(where: { $0.uuid == chosenUUID && $0.frame.width > 0 && $0.frame.height > 0 }) {
            return .chosen(index: index)
        }
        let fallbackIndex = candidates.firstIndex { $0.frame.width > 0 && $0.frame.height > 0 }
        return .fallback(index: fallbackIndex)
    }
}
