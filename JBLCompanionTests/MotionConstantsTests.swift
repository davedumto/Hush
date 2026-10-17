import XCTest
@testable import JBLCompanion

final class MotionConstantsTests: XCTestCase {
    // MARK: - §9.1/9.2/9.6 card transition selection

    func testExpandTransitionIsTheSpecSpringWhenMotionIsNotReduced() {
        XCTAssertEqual(
            MotionConstants.expandTransitionKind(reduceMotion: false),
            .spring(response: 0.42, dampingFraction: 0.78)
        )
    }

    func testExpandTransitionIsACrossfadeUnderReduceMotion() {
        XCTAssertEqual(
            MotionConstants.expandTransitionKind(reduceMotion: true),
            .crossfade(duration: 0.16)
        )
    }

    func testCollapseTransitionIsTheSpecSpringWhenMotionIsNotReduced() {
        XCTAssertEqual(
            MotionConstants.collapseTransitionKind(reduceMotion: false),
            .spring(response: 0.28, dampingFraction: 1.0)
        )
    }

    func testCollapseTransitionIsACrossfadeUnderReduceMotion() {
        XCTAssertEqual(
            MotionConstants.collapseTransitionKind(reduceMotion: true),
            .crossfade(duration: 0.16)
        )
    }

    func testReducedMotionCrossfadeIsTheSameDurationForExpandAndCollapse() {
        // §9.6 doesn't distinguish direction — both become "a 160 ms ease in out crossfade."
        XCTAssertEqual(
            MotionConstants.expandTransitionKind(reduceMotion: true),
            MotionConstants.collapseTransitionKind(reduceMotion: true)
        )
    }

    // MARK: - §9.1 point 6 stagger delay table

    func testStaggerDelayTableMatchesTheGuideInOrder() {
        XCTAssertEqual(MotionConstants.staggerDelay(for: .topRow), 0.08)
        XCTAssertEqual(MotionConstants.staggerDelay(for: .hero), 0.11)
        XCTAssertEqual(MotionConstants.staggerDelay(for: .name), 0.14)
        XCTAssertEqual(MotionConstants.staggerDelay(for: .controls), 0.17)
    }

    func testStaggerDelaysAreStrictlyIncreasingInContentOrder() {
        let delays = MotionConstants.ContentBlock.allCases.map { MotionConstants.staggerDelay(for: $0) }
        XCTAssertEqual(delays, delays.sorted())
        XCTAssertEqual(Set(delays).count, delays.count) // no two blocks share a delay
    }

    func testStaggerDelayCollapsesToZeroUnderReduceMotion() {
        for block in MotionConstants.ContentBlock.allCases {
            XCTAssertEqual(MotionConstants.staggerDelay(for: block, reduceMotion: true), 0)
        }
    }

    func testStaggerDelayIsUnchangedWhenMotionIsNotReduced() {
        for block in MotionConstants.ContentBlock.allCases {
            XCTAssertEqual(
                MotionConstants.staggerDelay(for: block, reduceMotion: false),
                MotionConstants.staggerDelay(for: block)
            )
        }
    }

    // MARK: - §9.1 point 1 / §9.2 point 4 window-resize ordering

    func testExpandGrowsTheWindowBeforeAnimating() {
        XCTAssertEqual(MotionConstants.windowResizeOrdering(forExpanding: true), .growBeforeAnimating)
    }

    func testCollapseShrinksTheWindowAfterAnimating() {
        XCTAssertEqual(MotionConstants.windowResizeOrdering(forExpanding: false), .shrinkAfterAnimating)
    }
}
