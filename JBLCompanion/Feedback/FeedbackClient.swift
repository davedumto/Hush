import Foundation
import os.log

enum FeedbackSubmissionResult {
    case success
    /// The server rejected the request (4xx/413) with a human-readable reason, when one was
    /// decodable from the body — falls back to a generic message otherwise.
    case rejected(message: String)
    /// 429 — the server's own 10/hour per-IP-or-per-device limit. `retryAfterSeconds` is read
    /// from the Retry-After header when present.
    case rateLimited(retryAfterSeconds: Int?)
    case networkError
}

/// Talks to the hush-feedback backend (hush-feedback's integration spec: POST
/// https://www.hushapp.site/api/feedback). Plain AppKit/Foundation networking — no Bluetooth
/// involved, nothing here touches WriteGuard or any RFCOMM/BLE code.
@MainActor
final class FeedbackClient {
    static let shared = FeedbackClient()

    static let endpointURL = URL(string: "https://www.hushapp.site/api/feedback")!

    private let logger = Logger(subsystem: "com.davidejere.JBLCompanion", category: "FeedbackClient")
    private let session: URLSession
    private let clientUUIDKey = "feedbackClientUUID"

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A stable per-install UUID, generated once and persisted in UserDefaults — the server uses
    /// this for per-device rate limiting (10 requests/hour), separate from per-IP limiting.
    var clientUUID: String {
        if let existing = UserDefaults.standard.string(forKey: clientUUIDKey) {
            return existing
        }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: clientUUIDKey)
        return fresh
    }

    func submit(_ request: FeedbackRequest) async -> FeedbackSubmissionResult {
        var urlRequest = URLRequest(url: Self.endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            logger.error("Failed to encode feedback request: \(error.localizedDescription, privacy: .public)")
            return .rejected(message: "Could not prepare the report.")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { return .networkError }

            switch http.statusCode {
            case 200:
                return .success
            case 429:
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Int.init)
                return .rateLimited(retryAfterSeconds: retryAfter)
            case 400, 413, 405:
                return .rejected(message: Self.errorMessage(from: data) ?? "The server rejected the report (\(http.statusCode)).")
            default:
                logger.error("Unexpected feedback response status: \(http.statusCode, privacy: .public)")
                return .rejected(message: "Unexpected response (\(http.statusCode)).")
            }
        } catch {
            logger.error("Feedback submission failed: \(error.localizedDescription, privacy: .public)")
            return .networkError
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let error: String? }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).error
    }
}
