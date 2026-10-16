import XCTest
@testable import JBLCompanion

final class RequiredFontsTests: XCTestCase {
    func testAllSevenPostScriptNamesFromTheGuideAreListed() {
        XCTAssertEqual(RequiredFonts.postScriptNames, [
            "Fredoka-Bold", "Fredoka-SemiBold", "Fredoka-Medium",
            "Nunito-ExtraBold", "Nunito-Bold", "Nunito-SemiBold", "Nunito-Medium",
        ])
    }

    func testUnresolvedIsEmptyWhenEverythingResolves() {
        XCTAssertTrue(RequiredFonts.unresolved(resolves: { _ in true }).isEmpty)
    }

    func testUnresolvedListsEveryNameWhenNothingResolves() {
        XCTAssertEqual(RequiredFonts.unresolved(resolves: { _ in false }), RequiredFonts.postScriptNames)
    }

    func testUnresolvedListsOnlyTheNamesThatFailToResolve() {
        let unresolved = RequiredFonts.unresolved(resolves: { $0 != "Nunito-Medium" })
        XCTAssertEqual(unresolved, ["Nunito-Medium"])
    }
}
