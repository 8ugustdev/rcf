import Foundation

/// HTTP request descriptor — one type covers JSON, raw text/bytes, and multipart bodies.
nonisolated struct CloudflareRequest: Sendable {
    enum Method: String, Sendable {
        case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
    }

    enum Body: Sendable {
        case none
        case json(Data)
        /// Raw bytes with explicit content type (DNS export read, R2 upload, KV value).
        case raw(Data, contentType: String)
        case multipart(MultipartBody)
    }

    /// Path relative to the v4 base, e.g. "/zones/{id}/dns_records".
    var path: String
    var method: Method = .get
    var query: [URLQueryItem] = []
    var body: Body = .none

    init(path: String, method: Method = .get, query: [URLQueryItem] = [], body: Body = .none) {
        self.path = path
        self.method = method
        self.query = query
        self.body = body
    }

    /// JSON-body convenience: encodes `value` and attaches it.
    static func json<T: Encodable>(_ value: T, path: String, method: Method, query: [URLQueryItem] = []) throws -> CloudflareRequest {
        CloudflareRequest(path: path, method: method, query: query, body: .json(try JSONEncoder().encode(value)))
    }

    /// Raw-text convenience (e.g. R2 upload body, KV value write).
    static func text(_ string: String, contentType: String, path: String, method: Method, query: [URLQueryItem] = []) -> CloudflareRequest {
        CloudflareRequest(path: path, method: method, query: query, body: .raw(Data(string.utf8), contentType: contentType))
    }
}
