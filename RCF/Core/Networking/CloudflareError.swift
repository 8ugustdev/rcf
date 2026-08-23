import Foundation

/// Unified error surface for all Cloudflare API operations.
nonisolated enum CloudflareError: Error, Sendable {
    /// Envelope returned success=false — carries the API's error list.
    case api(code: Int, message: String, errors: [APIError])
    /// Non-2xx response that was not (or not only) an envelope failure.
    case http(status: Int, retryAfter: TimeInterval?)
    /// 429 with parsed Retry-After (seconds).
    case rateLimited(retryAfter: TimeInterval)
    /// 401 — bad token/key.
    case unauthorized
    /// Transport-level failure.
    case network(URLError)
    /// Body could not be decoded.
    case decoding(Error)
    /// Expected non-null result but got null (or vice versa).
    case emptyResult
    /// Local token-bucket throttle engaged before the request was sent.
    case throttled(retryAfter: TimeInterval)
    /// No authenticated profile (client used before login).
    case notAuthenticated

    struct APIError: Codable, Sendable {
        let code: Int
        let message: String
    }

    /// Short, secret-free message suitable for UI display.
    var userMessage: String {
        switch self {
        case let .api(_, message, _): message
        case let .http(status, _): "Server error (HTTP \(status))"
        case .rateLimited: "Rate limited by Cloudflare — try again shortly"
        case .unauthorized: "Invalid API token or key"
        case let .network(urlError): urlError.localizedDescription
        case .decoding: "Unexpected response from Cloudflare"
        case .emptyResult: "Empty result from Cloudflare"
        case .throttled: "Throttled locally to protect your API quota"
        case .notAuthenticated: "Not signed in"
        }
    }

    /// True when the cause is a missing token permission (drives degraded UX).
    var isPermissionDenied: Bool {
        switch self {
        case let .api(code, _, _): code == 9109 || code == 10000
        case let .http(status, _): status == 403
        default: false
        }
    }

    /// Retry-After hint when present (seconds).
    var retryAfter: TimeInterval? {
        switch self {
        case let .http(_, retryAfter): retryAfter
        case let .rateLimited(retryAfter): retryAfter
        case let .throttled(retryAfter): retryAfter
        default: nil
        }
    }
}
