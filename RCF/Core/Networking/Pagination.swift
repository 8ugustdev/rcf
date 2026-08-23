import Foundation

/// Pagination helpers for page-based and cursor-based listings.
nonisolated enum Pagination {
    /// Loops page-based requests until `total_pages` is exhausted.
    /// - Parameter type: explicit element type, e.g. `[Zone].self`.
    /// - Parameter requestForPage: builds the request for a given 1-based page number.
    static func paginate<T: Decodable & Sendable>(
        _ type: [T].Type,
        client: CloudflareClient,
        into requestForPage: @escaping @Sendable (Int) -> CloudflareRequest
    ) async throws -> (items: [T], info: ResultInfo?) {
        var all: [T] = []
        var info: ResultInfo?
        var page = 1
        while true {
            let (items, pageResultInfo): ([T], ResultInfo?) = try await client.sendList(requestForPage(page))
            all.append(contentsOf: items)
            info = pageResultInfo ?? info
            let totalPages = pageResultInfo?.totalPages ?? 1
            guard page < totalPages, !items.isEmpty else { break }
            page += 1
        }
        return (all, info)
    }

    /// Loops cursor-based listings (R2 objects) until `is_truncated` is false.
    /// - Parameter type: explicit element type, e.g. `[R2Object].self`.
    /// - Parameter requestForCursor: builds the request for a given continuation cursor.
    static func paginateCursor<T: Decodable & Sendable>(
        _ type: [T].Type,
        client: CloudflareClient,
        into requestForCursor: @escaping @Sendable (String?) -> CloudflareRequest
    ) async throws -> [T] {
        var all: [T] = []
        var cursor: String? = nil
        var truncated = false
        repeat {
            let (items, info): ([T], ResultInfo?) = try await client.sendList(requestForCursor(cursor))
            all.append(contentsOf: items)
            cursor = info?.cursor
            truncated = info?.isTruncated ?? false
        } while cursor != nil && truncated
        return all
    }
}
