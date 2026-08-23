import Foundation

/// Cloudflare v4 response envelope.
nonisolated struct CloudflareResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let errors: [CloudflareError.APIError]
    let messages: [CloudflareError.APIError]
    let result: T?
    let resultInfo: ResultInfo?

    enum CodingKeys: String, CodingKey {
        case success, errors, messages, result
        case resultInfo = "result_info"
    }
}

/// Pagination metadata from `result_info`.
nonisolated struct ResultInfo: Decodable, Sendable {
    let page: Int?
    let perPage: Int?
    let totalCount: Int?
    let totalPages: Int?
    let count: Int?
    /// R2 object listings paginate by cursor instead of page numbers.
    let cursor: String?
    let isTruncated: Bool?

    enum CodingKeys: String, CodingKey {
        case page, count, cursor
        case perPage = "per_page"
        case totalCount = "total_count"
        case totalPages = "total_pages"
        case isTruncated = "is_truncated"
    }
}

/// Placeholder for endpoints whose `result` is JSON null (DELETE, purge, etc.).
nonisolated struct NullResult: Decodable, Sendable {
    init(from decoder: Decoder) throws {
        // Accept null or any content — result is ignored for void endpoints.
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            _ = try? container.decode(JSONValue.self)
        }
    }
}
