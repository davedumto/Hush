import XCTest
@testable import JBLCompanion

final class DisplayResolverTests: XCTestCase {
    private let mainFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let secondFrame = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

    func testNoSavedPreferenceFallsBackToTheFirstDisplay() {
        let candidates = [
            DisplayResolver.Candidate(uuid: "main-uuid", frame: mainFrame),
            DisplayResolver.Candidate(uuid: "second-uuid", frame: secondFrame),
        ]
        XCTAssertEqual(DisplayResolver.resolve(chosenUUID: nil, candidates: candidates), .fallback(index: 0))
    }

    func testSavedPreferenceMatchingAConnectedDisplayIsUsed() {
        let candidates = [
            DisplayResolver.Candidate(uuid: "main-uuid", frame: mainFrame),
            DisplayResolver.Candidate(uuid: "second-uuid", frame: secondFrame),
        ]
        XCTAssertEqual(DisplayResolver.resolve(chosenUUID: "second-uuid", candidates: candidates), .chosen(index: 1))
    }

    // MARK: - The saved position is outside every connected display

    func testSavedPreferenceNotAmongConnectedDisplaysFallsBackToTheFirstOne() {
        let candidates = [
            DisplayResolver.Candidate(uuid: "main-uuid", frame: mainFrame),
            DisplayResolver.Candidate(uuid: "second-uuid", frame: secondFrame),
        ]
        // "unplugged-external-uuid" was a display that's no longer connected.
        XCTAssertEqual(DisplayResolver.resolve(chosenUUID: "unplugged-external-uuid", candidates: candidates), .fallback(index: 0))
    }

    func testSavedPreferenceMatchingAZeroSizeFrameCountsAsNotConnected() {
        // A degenerate/disconnected display read can still report a UUID match with an empty
        // frame — that's not a usable display to place the island on either.
        let candidates = [
            DisplayResolver.Candidate(uuid: "main-uuid", frame: mainFrame),
            DisplayResolver.Candidate(uuid: "zero-size-uuid", frame: .zero),
        ]
        XCTAssertEqual(DisplayResolver.resolve(chosenUUID: "zero-size-uuid", candidates: candidates), .fallback(index: 0))
    }

    func testFallbackSkipsLeadingZeroSizeDisplaysToFindAUsableOne() {
        let candidates = [
            DisplayResolver.Candidate(uuid: "zero-size-uuid", frame: .zero),
            DisplayResolver.Candidate(uuid: "main-uuid", frame: mainFrame),
        ]
        XCTAssertEqual(DisplayResolver.resolve(chosenUUID: nil, candidates: candidates), .fallback(index: 1))
    }

    func testNoConnectedDisplaysAtAllReturnsNilFallbackIndex() {
        XCTAssertEqual(DisplayResolver.resolve(chosenUUID: "anything", candidates: []), .fallback(index: nil))
    }

    func testAllConnectedDisplaysHaveZeroSizeFramesReturnsNilFallbackIndex() {
        let candidates = [
            DisplayResolver.Candidate(uuid: "a", frame: .zero),
            DisplayResolver.Candidate(uuid: "b", frame: .zero),
        ]
        XCTAssertEqual(DisplayResolver.resolve(chosenUUID: nil, candidates: candidates), .fallback(index: nil))
    }

    func testSavedPreferenceWithNilUUIDCandidateNeverMatchesByCoincidence() {
        // A connected display whose stableDisplayUUIDString happened to read as nil must never be
        // treated as "the chosen one" just because chosenUUID is also nil ("no preference saved")
        // — a regression test for the `if let chosenUUID` guard specifically.
        let candidates = [
            DisplayResolver.Candidate(uuid: nil, frame: mainFrame),
            DisplayResolver.Candidate(uuid: "second-uuid", frame: secondFrame),
        ]
        XCTAssertEqual(DisplayResolver.resolve(chosenUUID: nil, candidates: candidates), .fallback(index: 0))
    }
}
