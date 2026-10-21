import XCTest
@testable import JBLCompanion

final class FeedbackRequestBuilderTests: XCTestCase {
    private func makeDescription(whatHappened: String? = "It crashed") -> FeedbackDescription {
        FeedbackDescription(whatHappened: whatHappened, steps: nil, expected: nil, featureDescription: nil)
    }

    func testBuildSucceedsWithATitleAndANonEmptyDescriptionField() throws {
        let request = try FeedbackRequestBuilder.build(type: .bug, title: "Stuck on Connecting", description: makeDescription())
        XCTAssertEqual(request.type, .bug)
        XCTAssertEqual(request.title, "Stuck on Connecting")
        XCTAssertEqual(request.description.whatHappened, "It crashed")
        XCTAssertEqual(request.honeypot, "")
    }

    func testBuildThrowsOnAnEmptyTitle() {
        XCTAssertThrowsError(try FeedbackRequestBuilder.build(type: .bug, title: "   ", description: makeDescription())) { error in
            XCTAssertEqual(error as? FeedbackValidationError, .emptyTitle)
        }
    }

    func testBuildThrowsWhenEveryDescriptionFieldIsEmpty() {
        let empty = FeedbackDescription(whatHappened: "  ", steps: nil, expected: "", featureDescription: nil)
        XCTAssertThrowsError(try FeedbackRequestBuilder.build(type: .bug, title: "Title", description: empty)) { error in
            XCTAssertEqual(error as? FeedbackValidationError, .emptyDescription)
        }
    }

    func testBuildAcceptsAFeatureRequestDescribedOnlyByFeatureDescription() throws {
        let description = FeedbackDescription(whatHappened: nil, steps: nil, expected: nil, featureDescription: "EQ controls")
        let request = try FeedbackRequestBuilder.build(type: .feature, title: "EQ", description: description)
        XCTAssertEqual(request.description.featureDescription, "EQ controls")
    }

    func testBuildTruncatesATitleLongerThanTheServersOwnLimit() throws {
        let longTitle = String(repeating: "a", count: FeedbackRequestBuilder.titleLimit + 50)
        let request = try FeedbackRequestBuilder.build(type: .bug, title: longTitle, description: makeDescription())
        XCTAssertEqual(request.title.count, FeedbackRequestBuilder.titleLimit)
    }

    func testBuildTruncatesATextFieldLongerThanTheServersOwnLimit() throws {
        let longText = String(repeating: "b", count: FeedbackRequestBuilder.textFieldLimit + 100)
        let request = try FeedbackRequestBuilder.build(type: .bug, title: "Title", description: makeDescription(whatHappened: longText))
        XCTAssertEqual(request.description.whatHappened?.count, FeedbackRequestBuilder.textFieldLimit)
    }

    func testBuildTruncatesDiagnosticsLongerThanTheServersOwnLimit() throws {
        let longDiagnostics = String(repeating: "c", count: FeedbackRequestBuilder.diagnosticsLimit + 500)
        let request = try FeedbackRequestBuilder.build(type: .bug, title: "Title", description: makeDescription(), diagnostics: longDiagnostics)
        XCTAssertEqual(request.diagnostics?.count, FeedbackRequestBuilder.diagnosticsLimit)
    }

    func testBuildAcceptsAnEmptyReplyEmailAsNoReplyEmailAtAll() throws {
        let request = try FeedbackRequestBuilder.build(type: .bug, title: "Title", description: makeDescription(), replyEmail: "   ")
        XCTAssertNil(request.replyEmail)
    }

    func testBuildAcceptsAWellFormedReplyEmail() throws {
        let request = try FeedbackRequestBuilder.build(type: .bug, title: "Title", description: makeDescription(), replyEmail: "me@example.com")
        XCTAssertEqual(request.replyEmail, "me@example.com")
    }

    func testBuildThrowsOnAMalformedReplyEmail() {
        XCTAssertThrowsError(
            try FeedbackRequestBuilder.build(type: .bug, title: "Title", description: makeDescription(), replyEmail: "not-an-email")
        ) { error in
            XCTAssertEqual(error as? FeedbackValidationError, .invalidReplyEmail)
        }
    }

    func testBuildTrimsWhitespaceFromTheTitle() throws {
        let request = try FeedbackRequestBuilder.build(type: .bug, title: "  Title  ", description: makeDescription())
        XCTAssertEqual(request.title, "Title")
    }

    func testBuildOmitsEmptyOptionalFieldsEntirely() throws {
        let request = try FeedbackRequestBuilder.build(type: .bug, title: "Title", description: makeDescription(), model: "   ")
        XCTAssertNil(request.model)
    }
}
