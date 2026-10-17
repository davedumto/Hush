import XCTest
@testable import JBLCompanion

final class DockPlacementTests: XCTestCase {
    // design/DESIGN_GUIDE.md's own environment notes: external 1920x1200, no notch.
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1200)
    private var visibleFrame: CGRect { CGRect(x: 0, y: 0, width: 1920, height: 1170) } // 30pt Dock-ish inset at the bottom

    // MARK: - Edge geometry (bottom/left/right — .top stays IslandGeometry's own job)

    func testBottomPillSitsAboveTheVisibleFrameBottom() {
        let size = DockPlacement.collapsedPillSize(for: .bottom)
        let frame = DockPlacement.frame(for: size, edge: .bottom, offset: 0, visibleFrame: visibleFrame, margin: DockPlacement.edgeMargin(for: .bottom))
        XCTAssertEqual(frame.minY, visibleFrame.minY + 12)
        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertEqual(size, CGSize(width: 46, height: 34))
    }

    func testLeftPillSitsTenPointsFromTheLeftEdgeVerticallyCentered() {
        let size = DockPlacement.collapsedPillSize(for: .left)
        let frame = DockPlacement.frame(for: size, edge: .left, offset: 0, visibleFrame: visibleFrame, margin: DockPlacement.edgeMargin(for: .left))
        XCTAssertEqual(frame.minX, visibleFrame.minX + 10)
        XCTAssertEqual(frame.midY, visibleFrame.midY)
        XCTAssertEqual(size, CGSize(width: 34, height: 46))
    }

    func testRightPillMirrorsLeft() {
        let size = DockPlacement.collapsedPillSize(for: .right)
        let frame = DockPlacement.frame(for: size, edge: .right, offset: 0, visibleFrame: visibleFrame, margin: DockPlacement.edgeMargin(for: .right))
        XCTAssertEqual(frame.maxX, visibleFrame.maxX - 10)
        XCTAssertEqual(frame.midY, visibleFrame.midY)
    }

    func testOffsetShiftsAlongTheEdgeNotAwayFromIt() {
        let size = DockPlacement.collapsedPillSize(for: .bottom)
        let frame = DockPlacement.frame(for: size, edge: .bottom, offset: 100, visibleFrame: visibleFrame, margin: 12)
        XCTAssertEqual(frame.midX, visibleFrame.midX + 100)
        XCTAssertEqual(frame.minY, visibleFrame.minY + 12) // distance from the edge is unaffected
    }

    func testCardGrowsAwayFromTheDockedEdge() {
        // Bottom: the pill's bottom edge and the card's bottom edge line up (both anchored to the
        // same visibleFrame.minY + margin); the card just extends further upward.
        let pill = DockPlacement.frame(for: DockPlacement.collapsedPillSize(for: .bottom), edge: .bottom, offset: 0, visibleFrame: visibleFrame, margin: 12)
        let card = DockPlacement.frame(for: CGSize(width: 374, height: 470), edge: .bottom, offset: 0, visibleFrame: visibleFrame, margin: 12)
        XCTAssertEqual(pill.minY, card.minY)
        XCTAssertGreaterThan(card.maxY, pill.maxY)
    }

    // MARK: - Offset range / 8pt clamping

    func testOffsetRangeKeepsSizeInsideVisibleFrameWithMargin() throws {
        let range = DockPlacement.offsetRange(forSize: CGSize(width: 374, height: 470), edge: .bottom, visibleFrame: visibleFrame, margin: 8)
        let range2 = try XCTUnwrap(range)
        // At the extreme, the card's left edge must sit exactly at visibleFrame.minX + margin.
        let frameAtMin = DockPlacement.frame(for: CGSize(width: 374, height: 470), edge: .bottom, offset: range2.lowerBound, visibleFrame: visibleFrame, margin: 12)
        XCTAssertEqual(frameAtMin.minX, visibleFrame.minX + 8, accuracy: 0.001)
    }

    func testOffsetRangeIsNilWhenSizeCannotFitAtAll() {
        let tinyVisibleFrame = CGRect(x: 0, y: 0, width: 50, height: 50)
        let range = DockPlacement.offsetRange(forSize: CGSize(width: 374, height: 470), edge: .bottom, visibleFrame: tinyVisibleFrame, margin: 8)
        XCTAssertNil(range)
    }

    // MARK: - clampedOffset (collapsed + expanded together)

    func testClampedOffsetKeepsBothCollapsedAndExpandedInsideTheVisibleFrame() {
        let collapsed = DockPlacement.collapsedPillSize(for: .bottom)
        let expanded = CGSize(width: 374, height: 470)
        // Try to drag way off to the right — should clamp, not pass through unchanged.
        let clamped = DockPlacement.clampedOffset(10_000, collapsedSize: collapsed, expandedSize: expanded, edge: .bottom, visibleFrame: visibleFrame)
        let cardFrame = DockPlacement.frame(for: expanded, edge: .bottom, offset: clamped, visibleFrame: visibleFrame, margin: DockPlacement.edgeMargin(for: .bottom))
        XCTAssertEqual(cardFrame.maxX, visibleFrame.maxX - 8, accuracy: 0.001)
    }

    func testClampedOffsetLeavesAnInRangeValueUnchanged() {
        let collapsed = DockPlacement.collapsedPillSize(for: .left)
        let expanded = CGSize(width: 296, height: 470)
        let clamped = DockPlacement.clampedOffset(20, collapsedSize: collapsed, expandedSize: expanded, edge: .left, visibleFrame: visibleFrame)
        XCTAssertEqual(clamped, 20)
    }

    func testClampedOffsetUsesTheMoreRestrictiveOfTheTwoSizes() {
        // The expanded card is far bigger than the collapsed pill, so its own range should be the
        // binding constraint — the clamped value must respect the *card's* bounds, not the pill's
        // looser ones.
        let collapsed = DockPlacement.collapsedPillSize(for: .bottom)
        let expanded = CGSize(width: 374, height: 470)
        let pillOnlyRange = try! XCTUnwrap(DockPlacement.offsetRange(forSize: collapsed, edge: .bottom, visibleFrame: visibleFrame, margin: 8))
        let clamped = DockPlacement.clampedOffset(pillOnlyRange.upperBound, collapsedSize: collapsed, expandedSize: expanded, edge: .bottom, visibleFrame: visibleFrame)
        XCTAssertLessThan(clamped, pillOnlyRange.upperBound)
    }

    func testClampedOffsetFallsBackToZeroWhenNothingFits() {
        let tinyVisibleFrame = CGRect(x: 0, y: 0, width: 50, height: 50)
        let clamped = DockPlacement.clampedOffset(100, collapsedSize: CGSize(width: 46, height: 34), expandedSize: CGSize(width: 374, height: 470), edge: .bottom, visibleFrame: tinyVisibleFrame)
        XCTAssertEqual(clamped, 0)
    }

    // MARK: - Drag vs. click threshold

    func testSmallMovementIsNotADrag() {
        XCTAssertFalse(DockPlacement.isDrag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 2, y: 1)))
    }

    func testMovementPastTheThresholdIsADrag() {
        XCTAssertTrue(DockPlacement.isDrag(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 0)))
    }

    func testMovementExactlyAtTheThresholdIsNotYetADrag() {
        XCTAssertFalse(DockPlacement.isDrag(from: .zero, to: CGPoint(x: DockPlacement.dragThreshold, y: 0)))
    }

    // MARK: - Collapse-move-expand ordering

    func testChangingEdgeWhileExpandedCollapsesFirst() {
        XCTAssertEqual(DockPlacement.edgeChangeOrdering(isExpanded: true), .collapseFirst)
    }

    func testChangingEdgeWhileCollapsedMovesDirectly() {
        XCTAssertEqual(DockPlacement.edgeChangeOrdering(isExpanded: false), .moveDirectly)
    }
}
