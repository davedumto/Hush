import XCTest
@testable import JBLCompanion

final class IslandMotionTests: XCTestCase {
    func testProgressAtZeroTimeIsZero() {
        let spring = IslandMotion.Spring(duration: 0.4, bounce: 0.25)
        XCTAssertEqual(spring.progress(at: 0), 0)
    }

    func testProgressApproachesOneAsTimeGrows() {
        let spring = IslandMotion.Spring(duration: 0.4, bounce: 0)
        XCTAssertEqual(spring.progress(at: 5), 1, accuracy: 0.01)
    }

    func testZeroBounceHasNoOvershoot() {
        let spring = IslandMotion.Spring(duration: 0.3, bounce: 0)
        XCTAssertEqual(spring.overshoot, 0)
    }

    func testPositiveBounceHasPositiveOvershoot() {
        let spring = IslandMotion.Spring(duration: 0.44, bounce: 0.25)
        XCTAssertGreaterThan(spring.overshoot, 0)
    }

    func testLimitedReducesBounceWhenOvershootWouldExceedLimit() {
        let spring = IslandMotion.Spring(duration: 0.44, bounce: 0.25)
        // A huge travel with the growing spring's own overshoot share would swing way past 1pt.
        let limited = spring.limited(travel: 1000, limit: 1)
        XCTAssertLessThan(limited.bounce, spring.bounce)
    }

    func testLimitedLeavesSpringUnchangedWhenWithinLimit() {
        let spring = IslandMotion.Spring(duration: 0.44, bounce: 0.25)
        // Tiny travel — the absolute overshoot in points is small even with full bounce.
        let limited = spring.limited(travel: 0.001, limit: 12)
        XCTAssertEqual(limited, spring)
    }

    func testSizeAtTimeEqualsTargetWhenSideUnchanged() {
        let from = CGSize(width: 100, height: 50)
        let to = CGSize(width: 100, height: 80)
        let size = IslandMotion.size(at: 0.1, from: from, to: to)
        XCTAssertEqual(size.width, 100)
    }

    func testSizeAtLargeTimeSettlesNearTarget() {
        let from = CGSize(width: 100, height: 50)
        let to = CGSize(width: 480, height: 150)
        let size = IslandMotion.size(at: 2, from: from, to: to)
        XCTAssertEqual(size.width, to.width, accuracy: 0.5)
        XCTAssertEqual(size.height, to.height, accuracy: 0.5)
    }

    func testEnvelopeForShrinkIsExactlyTheLargerSize() {
        // Shrinking never overshoots, so the envelope is just the larger (starting) size.
        let from = CGSize(width: 480, height: 150)
        let to = CGSize(width: 60, height: 32)
        let envelope = IslandMotion.envelope(from: from, to: to)
        XCTAssertEqual(envelope.width, 480)
        XCTAssertEqual(envelope.height, 150)
    }

    func testEnvelopeForGrowthIsAtLeastTheTargetSize() {
        let from = CGSize(width: 60, height: 32)
        let to = CGSize(width: 480, height: 150)
        let envelope = IslandMotion.envelope(from: from, to: to)
        XCTAssertGreaterThanOrEqual(envelope.width, to.width)
        XCTAssertGreaterThanOrEqual(envelope.height, to.height)
    }

    func testEnvelopeOvershootNeverExceedsTheOvershootLimitByMuch() {
        let from = CGSize(width: 60, height: 32)
        let to = CGSize(width: 480, height: 150)
        let envelope = IslandMotion.envelope(from: from, to: to)
        // The spring's own `limited(travel:limit:)` caps the swing at overshootLimit (12pt);
        // allow a little slack for rounding.
        XCTAssertLessThanOrEqual(envelope.width - to.width, IslandMotion.overshootLimit + 1)
        XCTAssertLessThanOrEqual(envelope.height - to.height, IslandMotion.overshootLimit + 1)
    }

    func testReservationKeepsWholeEqualMargins() {
        let reserved = CGSize(width: 490, height: 150)
        let size = CGSize(width: 480, height: 150)
        let result = IslandMotion.reservation(reserved, centring: size)
        // Margin on each side should be whole and equal, so width grows by an even amount.
        XCTAssertEqual((result.width - size.width).truncatingRemainder(dividingBy: 2), 0)
        XCTAssertGreaterThanOrEqual(result.width, reserved.width)
    }

    func testReservationNeverShrinksBelowTheTargetSize() {
        let reserved = CGSize(width: 10, height: 10) // smaller than size — degenerate input
        let size = CGSize(width: 480, height: 150)
        let result = IslandMotion.reservation(reserved, centring: size)
        XCTAssertGreaterThanOrEqual(result.width, size.width)
        XCTAssertGreaterThanOrEqual(result.height, size.height)
    }

    func testFramesEndsExactlyAtTarget() {
        let from = CGSize(width: 60, height: 32)
        let to = CGSize(width: 480, height: 150)
        let result = IslandMotion.frames(from: from, to: to)
        XCTAssertEqual(result.sizes.last, to)
        XCTAssertEqual(result.keyTimes.last, 1)
        XCTAssertGreaterThan(result.duration, 0)
    }

    func testSettlingTimeIsZeroWhenAlreadyAtTarget() {
        let size = CGSize(width: 100, height: 50)
        // Every sample is already within settledDistance of the target from time 0.
        XCTAssertLessThanOrEqual(IslandMotion.settlingTime(from: size, to: size), 1.0 / 240)
    }
}
