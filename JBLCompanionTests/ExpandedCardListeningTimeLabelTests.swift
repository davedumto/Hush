import XCTest
@testable import JBLCompanion

/// `ExpandedCard.listeningTimeLabel(forSeconds:)` — `ExpandedCard`'s own `footer` doc comment on
/// why this is a plain view-layer helper rather than a `CardConditionResolver` function.
final class ExpandedCardListeningTimeLabelTests: XCTestCase {
    func testZeroSecondsShowsNothing() {
        XCTAssertNil(ExpandedCard.listeningTimeLabel(forSeconds: 0))
    }

    func testBelowAFullMinuteShowsNothing() {
        XCTAssertNil(ExpandedCard.listeningTimeLabel(forSeconds: 59))
    }

    func testExactlyOneMinute() {
        XCTAssertEqual(ExpandedCard.listeningTimeLabel(forSeconds: 60), "1M MEDIA PLAYBACK")
    }

    func testMinutesOnly() {
        XCTAssertEqual(ExpandedCard.listeningTimeLabel(forSeconds: 42 * 60), "42M MEDIA PLAYBACK")
    }

    func testExactlyOneHourShowsNoMinutesRemainder() {
        XCTAssertEqual(ExpandedCard.listeningTimeLabel(forSeconds: 60 * 60), "1H MEDIA PLAYBACK")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(ExpandedCard.listeningTimeLabel(forSeconds: 90 * 60), "1H 30M MEDIA PLAYBACK")
    }

    func testMultipleHours() {
        XCTAssertEqual(ExpandedCard.listeningTimeLabel(forSeconds: 2 * 60 * 60 + 15 * 60), "2H 15M MEDIA PLAYBACK")
    }

    func testPartialSecondsWithinAMinuteAreTruncatedNotRounded() {
        // 1 minute 59.9 seconds — still reads as "1M," not rounded up to "2M."
        XCTAssertEqual(ExpandedCard.listeningTimeLabel(forSeconds: 119.9), "1M MEDIA PLAYBACK")
    }
}
