import XCTest
@testable import JBLCompanion

final class IslandShapeTests: XCTestCase {
    // MARK: - cardRadius

    /// Must equal ExpandedCard's own hardcoded `cornerRadius: 33` exactly, not just
    /// approximately — this value is the native backdrop drawn *underneath* that SwiftUI shape,
    /// and any smaller radius here leaves its own flatter corner sticking out past the SwiftUI
    /// card's tighter curve (reported directly: "the orange line is inside and there is white
    /// overflow" — a real, visually confirmed bug, not a guess).
    func testCardRadiusAtCardHeightMatchesExpandedCardsOwnCornerRadius() {
        XCTAssertEqual(IslandShape.cardRadius(height: 500), 33)
    }

    func testCardRadiusScalesWithHeightBelowTheCap() {
        // 0.34 * 50 = 17, well under the 33 cap — still scaling, not yet flattened out.
        XCTAssertEqual(IslandShape.cardRadius(height: 50), 17)
    }

    func testCardRadiusNeverExceedsTheCapRegardlessOfHeight() {
        XCTAssertEqual(IslandShape.cardRadius(height: 10_000), 33)
    }

    // MARK: - pillRadius

    func testPillRadiusIsHalfHeight() {
        XCTAssertEqual(IslandShape.pillRadius(height: 52), 26)
    }

    // MARK: - path

    func testPathWithAnOversizedRadiusStillProducesTheRequestedBounds() {
        // A 20x10 rect asking for a 33pt radius can't have more than 5pt (half of 10) without the
        // rounded corners overlapping each other — this only checks the path doesn't degenerate
        // (e.g. clamp to a point or balloon past the rect) when that clamp kicks in internally;
        // CGPath's own bounding box is the same full rect regardless of corner radius.
        let path = IslandShape.path(size: CGSize(width: 20, height: 10), inset: 0, cornerRadius: 33)
        let bounds = path.boundingBoxOfPath
        XCTAssertEqual(bounds.width, 20, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 10, accuracy: 0.01)
    }

    func testPathInsetShrinksTheRect() {
        let path = IslandShape.path(size: CGSize(width: 100, height: 50), inset: 10, cornerRadius: 10)
        let bounds = path.boundingBoxOfPath
        XCTAssertEqual(bounds.width, 80, accuracy: 0.01)
        XCTAssertEqual(bounds.height, 30, accuracy: 0.01)
    }
}
