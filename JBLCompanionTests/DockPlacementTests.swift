import XCTest
@testable import JBLCompanion

final class DockPlacementTests: XCTestCase {
    // design/DESIGN_GUIDE.md's own environment notes: external 1920x1200, no notch.
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1200)
    private var visibleFrame: CGRect { CGRect(x: 0, y: 0, width: 1920, height: 1170) } // 30pt Dock-ish inset at the bottom

    // MARK: - Edge geometry (bottom/left/right — .top stays IslandGeometry's own job)

    func testBottomPillSitsAboveTheVisibleFrameBottom() {
        let size = DockPlacement.collapsedPillSize(for: .bottom, diameter: DockPlacement.collapsedPillDiameter)
        let frame = DockPlacement.frame(for: size, edge: .bottom, offset: 0, visibleFrame: visibleFrame, margin: DockPlacement.edgeMargin(for: .bottom))
        XCTAssertEqual(frame.minY, visibleFrame.minY + DockPlacement.edgeMargin(for: .bottom))
        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertEqual(size, CGSize(width: DockPlacement.collapsedPillDiameter, height: DockPlacement.collapsedPillDiameter))
    }

    func testLeftPillSitsAtTheDefaultMarginFromTheLeftEdgeVerticallyCentered() {
        let size = DockPlacement.collapsedPillSize(for: .left, diameter: DockPlacement.collapsedPillDiameter)
        let frame = DockPlacement.frame(for: size, edge: .left, offset: 0, visibleFrame: visibleFrame, margin: DockPlacement.edgeMargin(for: .left))
        XCTAssertEqual(frame.minX, visibleFrame.minX + DockPlacement.edgeMargin(for: .left))
        XCTAssertEqual(frame.midY, visibleFrame.midY)
        XCTAssertEqual(size, CGSize(width: DockPlacement.collapsedPillDiameter, height: DockPlacement.collapsedPillDiameter))
    }

    func testCollapsedPillIsTheSameCircularSizeOnEveryEdge() {
        // A circle, deliberately deviating from the guide's own elongated 46x34/34x46 pill (see
        // CollapsedPill's own doc comment / CLAUDE.md) — there's no long axis left to vary by
        // edge, which is also what fixed the old flex/stack background mismatch when switching
        // between a horizontal and a vertical dock.
        let sizes = DockEdge.allCases.map { DockPlacement.collapsedPillSize(for: $0, diameter: DockPlacement.collapsedPillDiameter) }
        for size in sizes {
            XCTAssertEqual(size.width, size.height)
            XCTAssertEqual(size, sizes[0])
        }
    }

    func testRightPillMirrorsLeft() {
        let size = DockPlacement.collapsedPillSize(for: .right, diameter: DockPlacement.collapsedPillDiameter)
        let frame = DockPlacement.frame(for: size, edge: .right, offset: 0, visibleFrame: visibleFrame, margin: DockPlacement.edgeMargin(for: .right))
        XCTAssertEqual(frame.maxX, visibleFrame.maxX - DockPlacement.edgeMargin(for: .right))
        XCTAssertEqual(frame.midY, visibleFrame.midY)
    }

    func testOffsetShiftsAlongTheEdgeNotAwayFromIt() {
        let size = DockPlacement.collapsedPillSize(for: .bottom, diameter: DockPlacement.collapsedPillDiameter)
        let frame = DockPlacement.frame(for: size, edge: .bottom, offset: 100, visibleFrame: visibleFrame, margin: 12)
        XCTAssertEqual(frame.midX, visibleFrame.midX + 100)
        XCTAssertEqual(frame.minY, visibleFrame.minY + 12) // distance from the edge is unaffected
    }

    func testCardGrowsAwayFromTheDockedEdge() {
        // Bottom: the pill's bottom edge and the card's bottom edge line up (both anchored to the
        // same visibleFrame.minY + margin); the card just extends further upward.
        let pill = DockPlacement.frame(for: DockPlacement.collapsedPillSize(for: .bottom, diameter: DockPlacement.collapsedPillDiameter), edge: .bottom, offset: 0, visibleFrame: visibleFrame, margin: 12)
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
        let collapsed = DockPlacement.collapsedPillSize(for: .bottom, diameter: DockPlacement.collapsedPillDiameter)
        let expanded = CGSize(width: 374, height: 470)
        // Try to drag way off to the right — should clamp, not pass through unchanged.
        let clamped = DockPlacement.clampedOffset(10_000, collapsedSize: collapsed, expandedSize: expanded, edge: .bottom, visibleFrame: visibleFrame)
        let cardFrame = DockPlacement.frame(for: expanded, edge: .bottom, offset: clamped, visibleFrame: visibleFrame, margin: DockPlacement.edgeMargin(for: .bottom))
        XCTAssertEqual(cardFrame.maxX, visibleFrame.maxX - 8, accuracy: 0.001)
    }

    func testClampedOffsetLeavesAnInRangeValueUnchanged() {
        let collapsed = DockPlacement.collapsedPillSize(for: .left, diameter: DockPlacement.collapsedPillDiameter)
        let expanded = CGSize(width: 296, height: 470)
        let clamped = DockPlacement.clampedOffset(20, collapsedSize: collapsed, expandedSize: expanded, edge: .left, visibleFrame: visibleFrame)
        XCTAssertEqual(clamped, 20)
    }

    func testClampedOffsetUsesTheMoreRestrictiveOfTheTwoSizes() {
        // The expanded card is far bigger than the collapsed pill, so its own range should be the
        // binding constraint — the clamped value must respect the *card's* bounds, not the pill's
        // looser ones.
        let collapsed = DockPlacement.collapsedPillSize(for: .bottom, diameter: DockPlacement.collapsedPillDiameter)
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

    // MARK: - Corner docking

    func testCornerPointsAreTheVisibleFrameSFourCorners() {
        XCTAssertEqual(DockPlacement.cornerPoint(.topLeft, visibleFrame: visibleFrame), CGPoint(x: visibleFrame.minX, y: visibleFrame.maxY))
        XCTAssertEqual(DockPlacement.cornerPoint(.topRight, visibleFrame: visibleFrame), CGPoint(x: visibleFrame.maxX, y: visibleFrame.maxY))
        XCTAssertEqual(DockPlacement.cornerPoint(.bottomLeft, visibleFrame: visibleFrame), CGPoint(x: visibleFrame.minX, y: visibleFrame.minY))
        XCTAssertEqual(DockPlacement.cornerPoint(.bottomRight, visibleFrame: visibleFrame), CGPoint(x: visibleFrame.maxX, y: visibleFrame.minY))
    }

    func testNearestCornerFindsTheClosestCornerWithinSnapDistance() {
        let size = CGSize(width: 52, height: 52)
        // Flush exactly into the top-left corner — content's own top-left corner sits right on
        // visibleFrame's, distance 0.
        let flushTopLeft = CGRect(x: visibleFrame.minX, y: visibleFrame.maxY - size.height, width: size.width, height: size.height)
        XCTAssertEqual(DockPlacement.nearestCorner(contentFrame: flushTopLeft, visibleFrame: visibleFrame, snapDistance: 12), .topLeft)
    }

    func testNearestCornerIsNilWhenNothingIsCloseEnough() {
        let size = CGSize(width: 52, height: 52)
        let centered = CGRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
        XCTAssertNil(DockPlacement.nearestCorner(contentFrame: centered, visibleFrame: visibleFrame, snapDistance: 12))
    }

    func testNearestCornerIsNilWhenOnlyOneOfTheTwoEdgesIsClose() {
        // Flush against the left edge, but nowhere near the top or bottom — this used to be the
        // actual bug: a center-to-corner check could never be satisfied by any on-screen drop, so
        // corner docking never triggered at all, even when genuinely dropped in a corner (the
        // boundary clamp that keeps content on screen already puts the center a full radius away
        // from any literal corner point). Corner-to-corner measurement is what actually fixes
        // that, but it must still correctly reject a drop that's flush on only one axis.
        let size = CGSize(width: 52, height: 52)
        let flushLeftOnly = CGRect(x: visibleFrame.minX, y: visibleFrame.midY - size.height / 2, width: size.width, height: size.height)
        XCTAssertNil(DockPlacement.nearestCorner(contentFrame: flushLeftOnly, visibleFrame: visibleFrame, snapDistance: 12))
    }

    func testNearestCornerPicksWhicheverCornerIsActuallyClosest() {
        // Flush bottom-left exactly; top-left would require the content to also reach the top
        // edge, which it doesn't, so only bottom-left can possibly match.
        let size = CGSize(width: 52, height: 52)
        let flushBottomLeft = CGRect(x: visibleFrame.minX, y: visibleFrame.minY, width: size.width, height: size.height)
        XCTAssertEqual(DockPlacement.nearestCorner(contentFrame: flushBottomLeft, visibleFrame: visibleFrame, snapDistance: 12), .bottomLeft)
    }

    func testCornerFrameIsFlushIntoEachCornerByMargin() {
        let size = CGSize(width: 52, height: 52)
        let margin: CGFloat = 20

        let topLeft = DockPlacement.cornerFrame(for: size, corner: .topLeft, visibleFrame: visibleFrame, margin: margin)
        XCTAssertEqual(topLeft.minX, visibleFrame.minX + margin)
        XCTAssertEqual(topLeft.maxY, visibleFrame.maxY - margin)

        let topRight = DockPlacement.cornerFrame(for: size, corner: .topRight, visibleFrame: visibleFrame, margin: margin)
        XCTAssertEqual(topRight.maxX, visibleFrame.maxX - margin)
        XCTAssertEqual(topRight.maxY, visibleFrame.maxY - margin)

        let bottomLeft = DockPlacement.cornerFrame(for: size, corner: .bottomLeft, visibleFrame: visibleFrame, margin: margin)
        XCTAssertEqual(bottomLeft.minX, visibleFrame.minX + margin)
        XCTAssertEqual(bottomLeft.minY, visibleFrame.minY + margin)

        let bottomRight = DockPlacement.cornerFrame(for: size, corner: .bottomRight, visibleFrame: visibleFrame, margin: margin)
        XCTAssertEqual(bottomRight.maxX, visibleFrame.maxX - margin)
        XCTAssertEqual(bottomRight.minY, visibleFrame.minY + margin)
    }

    func testCornerFrameKeepsTheSameFlushCornerRegardlessOfSize() {
        // The actual bug being fixed: the collapsed quarter-disc and the much larger expanded card
        // both anchor to the exact same screen point, so expanding/collapsing from a corner never
        // has to displace it to make room — unlike edge docking's offset, there's no free axis for
        // a size change to shift.
        let margin: CGFloat = 20
        let small = DockPlacement.cornerFrame(for: CGSize(width: 52, height: 52), corner: .bottomRight, visibleFrame: visibleFrame, margin: margin)
        let big = DockPlacement.cornerFrame(for: CGSize(width: 374, height: 500), corner: .bottomRight, visibleFrame: visibleFrame, margin: margin)
        XCTAssertEqual(small.maxX, big.maxX)
        XCTAssertEqual(small.minY, big.minY)
    }

    func testQuarterCirclePathIsFlushInThatCornerAndCurvesAwayFromIt() {
        let size = CGSize(width: 52, height: 52)
        let flushCorners: [ScreenCorner: CGPoint] = [
            .bottomLeft: CGPoint(x: 0, y: 0), .bottomRight: CGPoint(x: size.width, y: 0),
            .topRight: CGPoint(x: size.width, y: size.height), .topLeft: CGPoint(x: 0, y: size.height),
        ]
        let farCorners: [ScreenCorner: CGPoint] = [
            .bottomLeft: CGPoint(x: size.width, y: size.height), .bottomRight: CGPoint(x: 0, y: size.height),
            .topRight: CGPoint(x: 0, y: 0), .topLeft: CGPoint(x: size.width, y: 0),
        ]
        for corner in ScreenCorner.allCases {
            let path = DockPlacement.quarterCirclePath(size: size, corner: corner)
            // Right at the flush corner itself — always inside (it's the arc's own center).
            XCTAssertTrue(path.contains(flushCorners[corner]!), "\(corner) quarter-disc doesn't cover its own flush corner")
            // Diagonally opposite — always outside a quarter-disc of this radius, proof the shape
            // actually curves away from its flush corner instead of filling the whole square.
            XCTAssertFalse(path.contains(farCorners[corner]!), "\(corner) quarter-disc unexpectedly covers its own far corner")
        }
    }

    // MARK: - Free-floating tray direction (owner spec, 2026-10-21)

    /// 1920x1170, matching `visibleFrame` above, carved into 9 equal 640x390 cells for easy math.
    private func pointIn(region: GridRegion) -> CGPoint {
        let cellWidth = visibleFrame.width / 3
        let cellHeight = visibleFrame.height / 3
        let col: CGFloat
        let row: CGFloat // 0 = bottom row, 2 = top row (AppKit y-up)
        switch region {
        case .topLeft: col = 0; row = 2
        case .topCenter: col = 1; row = 2
        case .topRight: col = 2; row = 2
        case .middleLeft: col = 0; row = 1
        case .center: col = 1; row = 1
        case .middleRight: col = 2; row = 1
        case .bottomLeft: col = 0; row = 0
        case .bottomCenter: col = 1; row = 0
        case .bottomRight: col = 2; row = 0
        }
        return CGPoint(x: visibleFrame.minX + cellWidth * (col + 0.5), y: visibleFrame.minY + cellHeight * (row + 0.5))
    }

    func testGridRegionFindsEachOfTheNineRegionsFromItsOwnMidpoint() {
        for region in GridRegion.allCases {
            XCTAssertEqual(DockPlacement.gridRegion(for: pointIn(region: region), visibleFrame: visibleFrame), region)
        }
    }

    func testGridRegionBoundaryTiesGoToTheRightColumn() {
        // Exactly on the left/middle column boundary.
        let onBoundary = CGPoint(x: visibleFrame.minX + visibleFrame.width / 3, y: visibleFrame.midY)
        XCTAssertEqual(DockPlacement.gridRegion(for: onBoundary, visibleFrame: visibleFrame), .center)
    }

    func testGridRegionBoundaryTiesGoToTheLowerRow() {
        // Exactly on the middle/top row boundary (AppKit y-up: higher y is higher on screen).
        let onBoundary = CGPoint(x: visibleFrame.midX, y: visibleFrame.minY + visibleFrame.height * 2 / 3)
        XCTAssertEqual(DockPlacement.gridRegion(for: onBoundary, visibleFrame: visibleFrame), .center)
        // Exactly on the bottom/middle row boundary.
        let onLowerBoundary = CGPoint(x: visibleFrame.midX, y: visibleFrame.minY + visibleFrame.height / 3)
        XCTAssertEqual(DockPlacement.gridRegion(for: onLowerBoundary, visibleFrame: visibleFrame), .bottomCenter)
    }

    func testTrayDirectionMatchesTheOwnersOwnTable() {
        XCTAssertEqual(DockPlacement.trayDirection(for: .topLeft), .down)
        XCTAssertEqual(DockPlacement.trayDirection(for: .topCenter), .down)
        XCTAssertEqual(DockPlacement.trayDirection(for: .topRight), .down)
        XCTAssertEqual(DockPlacement.trayDirection(for: .middleLeft), .right)
        XCTAssertEqual(DockPlacement.trayDirection(for: .center), .down)
        XCTAssertEqual(DockPlacement.trayDirection(for: .middleRight), .left)
        XCTAssertEqual(DockPlacement.trayDirection(for: .bottomLeft), .up)
        XCTAssertEqual(DockPlacement.trayDirection(for: .bottomCenter), .up)
        XCTAssertEqual(DockPlacement.trayDirection(for: .bottomRight), .up)
    }

    func testNotchDirectionIsAlwaysOppositeTheTrayDirection() {
        XCTAssertEqual(DockPlacement.notchDirection(for: .up), .down)
        XCTAssertEqual(DockPlacement.notchDirection(for: .down), .up)
        XCTAssertEqual(DockPlacement.notchDirection(for: .left), .right)
        XCTAssertEqual(DockPlacement.notchDirection(for: .right), .left)
    }

    func testTrayOriginSitsAdjacentToTheIslandNeverOverlappingIt() {
        let islandCenter = CGPoint(x: 500, y: 500)
        let islandSize = CGSize(width: 52, height: 52)
        let traySize = CGSize(width: 374, height: 500)
        let gap: CGFloat = 8

        let down = DockPlacement.trayOrigin(islandCenter: islandCenter, islandSize: islandSize, traySize: traySize, direction: .down, gap: gap)
        // Tray's top edge sits `gap` below the island's bottom edge.
        XCTAssertEqual(down.y + traySize.height, islandCenter.y - islandSize.height / 2 - gap)
        XCTAssertEqual(down.x + traySize.width / 2, islandCenter.x) // centered under the island

        let up = DockPlacement.trayOrigin(islandCenter: islandCenter, islandSize: islandSize, traySize: traySize, direction: .up, gap: gap)
        XCTAssertEqual(up.y, islandCenter.y + islandSize.height / 2 + gap)

        let right = DockPlacement.trayOrigin(islandCenter: islandCenter, islandSize: islandSize, traySize: traySize, direction: .right, gap: gap)
        XCTAssertEqual(right.x, islandCenter.x + islandSize.width / 2 + gap)

        let left = DockPlacement.trayOrigin(islandCenter: islandCenter, islandSize: islandSize, traySize: traySize, direction: .left, gap: gap)
        XCTAssertEqual(left.x + traySize.width, islandCenter.x - islandSize.width / 2 - gap)
    }

    func testClampedTrayOriginNeverTouchesTheDirectionAxis() {
        // A tray opening downward near the very left edge of the screen needs its x clamped
        // rightward to stay on screen — but its y (the direction axis, controlling that it's
        // genuinely below the island) must never move, or it could end up overlapping the island.
        let traySize = CGSize(width: 374, height: 500)
        let origin = CGPoint(x: -50, y: 300)
        let clamped = DockPlacement.clampedTrayOrigin(origin, traySize: traySize, visibleFrame: visibleFrame, direction: .down)
        XCTAssertEqual(clamped.y, origin.y)
        XCTAssertEqual(clamped.x, visibleFrame.minX)
    }

    func testClampedTrayOriginLeavesAnAlreadyOnScreenOriginUntouched() {
        let traySize = CGSize(width: 374, height: 500)
        let origin = CGPoint(x: 500, y: 400)
        let clamped = DockPlacement.clampedTrayOrigin(origin, traySize: traySize, visibleFrame: visibleFrame, direction: .down)
        XCTAssertEqual(clamped, origin)
    }

    func testNotchOffsetTracksTheIslandWhenThereIsRoom() {
        let traySize = CGSize(width: 374, height: 500)
        let trayOrigin = CGPoint(x: 0, y: 0)
        let islandCenter = CGPoint(x: trayOrigin.x + traySize.width / 2 + 20, y: 900) // 20pt right of tray's own center
        let offset = DockPlacement.notchOffset(
            islandCenter: islandCenter, trayOrigin: trayOrigin, traySize: traySize, direction: .up,
            cornerRadius: 33, notchHalfLength: 26
        )
        XCTAssertEqual(offset, 20)
    }

    func testNotchOffsetClampsAwayFromTheRoundedCorner() {
        let traySize = CGSize(width: 374, height: 500)
        let trayOrigin = CGPoint(x: 0, y: 0)
        // Island way off to the right — past where the notch could sit without overhanging the
        // tray's own rounded corner.
        let islandCenter = CGPoint(x: trayOrigin.x + traySize.width, y: 900)
        let cornerRadius: CGFloat = 33
        let notchHalfLength: CGFloat = 26
        let offset = DockPlacement.notchOffset(
            islandCenter: islandCenter, trayOrigin: trayOrigin, traySize: traySize, direction: .up,
            cornerRadius: cornerRadius, notchHalfLength: notchHalfLength
        )
        let maxOffset = traySize.width / 2 - cornerRadius - notchHalfLength
        XCTAssertEqual(offset, maxOffset)
    }

    func testTrayPlacementUsesThePreferredDirectionWhenItFits() {
        let islandCenter = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let islandSize = CGSize(width: 52, height: 52)
        let traySize = CGSize(width: 374, height: 500)
        let (origin, direction) = DockPlacement.trayPlacement(
            islandCenter: islandCenter, islandSize: islandSize, traySize: traySize, preferredDirection: .down,
            gap: 8, visibleFrame: visibleFrame
        )
        XCTAssertEqual(direction, .down)
        XCTAssertTrue(DockPlacement.trayFits(origin: origin, traySize: traySize, visibleFrame: visibleFrame))
    }

    func testTrayPlacementFlipsToTheOppositeDirectionWhenThePreferredOneDoesNotFit() {
        // Region 5 (center) prefers `.down`, but the island is placed low enough that a 500pt-tall
        // tray genuinely can't fit below it — only above. This is the owner's own example case.
        let islandSize = CGSize(width: 52, height: 52)
        let traySize = CGSize(width: 374, height: 500)
        let islandCenter = CGPoint(x: visibleFrame.midX, y: visibleFrame.minY + 100)
        let (origin, direction) = DockPlacement.trayPlacement(
            islandCenter: islandCenter, islandSize: islandSize, traySize: traySize, preferredDirection: .down,
            gap: 8, visibleFrame: visibleFrame
        )
        XCTAssertEqual(direction, .up)
        XCTAssertTrue(DockPlacement.trayFits(origin: origin, traySize: traySize, visibleFrame: visibleFrame))
        XCTAssertEqual(origin.y, islandCenter.y + islandSize.height / 2 + 8)
    }

    func testTrayPlacementClampsOnlyWhenNeitherDirectionFits() {
        // A tray taller than the entire visible frame can never fit either way — clamped output,
        // preferred direction preserved, same as `clampedTrayOrigin` on its own.
        let islandCenter = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let islandSize = CGSize(width: 52, height: 52)
        let oversizedTray = CGSize(width: 374, height: visibleFrame.height + 200)
        let (origin, direction) = DockPlacement.trayPlacement(
            islandCenter: islandCenter, islandSize: islandSize, traySize: oversizedTray, preferredDirection: .down,
            gap: 8, visibleFrame: visibleFrame
        )
        XCTAssertEqual(direction, .down)
        XCTAssertFalse(DockPlacement.trayFits(origin: origin, traySize: oversizedTray, visibleFrame: visibleFrame))
        let expected = DockPlacement.clampedTrayOrigin(
            DockPlacement.trayOrigin(islandCenter: islandCenter, islandSize: islandSize, traySize: oversizedTray, direction: .down, gap: 8),
            traySize: oversizedTray, visibleFrame: visibleFrame, direction: .down
        )
        XCTAssertEqual(origin, expected)
    }
}
