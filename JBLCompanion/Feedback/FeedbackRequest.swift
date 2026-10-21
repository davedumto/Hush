import Foundation

/// "bug" or "feature" — matches the server's own `type` enum exactly (hush-feedback's zod schema).
enum FeedbackType: String, Codable {
    case bug
    case feature
}

/// What goes in the `description` object. The server requires at least one of these fields to be
/// non-empty; which ones are meaningful depends on `type` (bug reports use the first three,
/// feature requests use `featureDescription`), but the wire format always sends the same shape.
struct FeedbackDescription: Codable {
    var whatHappened: String?
    var steps: String?
    var expected: String?
    var featureDescription: String?

    var isEmpty: Bool {
        [whatHappened, steps, expected, featureDescription].allSatisfy {
            ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// The exact JSON body POSTed to /api/feedback, per the hush-feedback integration spec. Built by
/// `FeedbackRequestBuilder`, never constructed with pre-truncated/pre-validated fields by hand —
/// that's what makes the builder's limits the single source of truth.
struct FeedbackRequest: Codable {
    var type: FeedbackType
    var title: String
    var description: FeedbackDescription
    var model: String?
    var replyEmail: String?
    var appVersion: String?
    var appBuild: String?
    var macosVersion: String?
    var macModel: String?
    var profileName: String?
    var locale: String?
    var diagnostics: String?
    var clientUuid: String?
    /// Always sent empty by a real client — see FeedbackRequestBuilder's own doc comment.
    var honeypot: String = ""
}

enum FeedbackValidationError: Error, Equatable {
    case emptyTitle
    case emptyDescription
    case invalidReplyEmail
}

/// Builds and validates a `FeedbackRequest` against the server's own limits (title ≤120,
/// free-text fields ≤2000, diagnostics ≤8000 — hush-feedback's zod schema), so a field that's too
/// long gets truncated client-side instead of round-tripping to the server just to find out via a
/// 400. Pure and synchronous: no networking, no UUID generation, no Bundle/ProcessInfo reads — the
/// caller supplies every piece of context, which is what makes this testable without mocking the
/// environment.
enum FeedbackRequestBuilder {
    static let titleLimit = 120
    static let textFieldLimit = 2000
    static let diagnosticsLimit = 8000

    static func build(
        type: FeedbackType,
        title: String,
        description: FeedbackDescription,
        model: String? = nil,
        replyEmail: String? = nil,
        appVersion: String? = nil,
        appBuild: String? = nil,
        macosVersion: String? = nil,
        macModel: String? = nil,
        profileName: String? = nil,
        locale: String? = nil,
        diagnostics: String? = nil,
        clientUuid: String? = nil
    ) throws -> FeedbackRequest {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw FeedbackValidationError.emptyTitle }

        guard !description.isEmpty else { throw FeedbackValidationError.emptyDescription }

        let trimmedEmail = replyEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedEmail.isEmpty && !isPlausibleEmail(trimmedEmail) {
            throw FeedbackValidationError.invalidReplyEmail
        }

        return FeedbackRequest(
            type: type,
            title: truncate(trimmedTitle, to: titleLimit),
            description: FeedbackDescription(
                whatHappened: truncateIfPresent(description.whatHappened, to: textFieldLimit),
                steps: truncateIfPresent(description.steps, to: textFieldLimit),
                expected: truncateIfPresent(description.expected, to: textFieldLimit),
                featureDescription: truncateIfPresent(description.featureDescription, to: textFieldLimit)
            ),
            model: truncateIfPresent(model, to: textFieldLimit),
            replyEmail: trimmedEmail.isEmpty ? nil : trimmedEmail,
            appVersion: appVersion,
            appBuild: appBuild,
            macosVersion: macosVersion,
            macModel: macModel,
            profileName: profileName,
            locale: locale,
            diagnostics: truncateIfPresent(diagnostics, to: diagnosticsLimit),
            clientUuid: clientUuid
        )
    }

    /// Deliberately permissive — this only protects the request from a server-side 400, it's not
    /// the server's own authoritative check. A real address is confirmed by the user actually
    /// getting a reply, not by this regex.
    private static func isPlausibleEmail(_ value: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func truncateIfPresent(_ value: String?, to limit: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : truncate(trimmed, to: limit)
    }

    private static func truncate(_ value: String, to limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit)) : value
    }
}
