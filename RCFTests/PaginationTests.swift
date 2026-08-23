import XCTest
@testable import RCF

/// Page-based and cursor-based pagination loops.
final class PaginationTests: XCTestCase {
    private func makeClient() -> CloudflareClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return CloudflareClient(auth: .token("t"), session: URLSession(configuration: config))
    }

    private func zoneJSON(id: String) -> String {
        """
        {"id":"\(id)","name":"\(id).com","status":"active","paused":false,"type":"full","development_mode":0,
         "name_servers":[],"plan":{"id":"p","name":"Free"},"account":{"id":"a","name":"acct"}}
        """
    }

    private func envelope(results: [String], page: Int, totalPages: Int) -> Data {
        Data("""
        {"success":true,"errors":[],"messages":[],"result":[\(results.joined(separator: ","))],
         "result_info":{"page":\(page),"per_page":2,"count":\(results.count),"total_count":\(totalPages * 2),"total_pages":\(totalPages)}}
        """.utf8)
    }

    func testPaginatesUntilTotalPages() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(.init(data: envelope(results: [zoneJSON(id: "z1"), zoneJSON(id: "z2")], page: 1, totalPages: 2)))
        MockURLProtocol.enqueue(.init(data: envelope(results: [zoneJSON(id: "z3")], page: 2, totalPages: 2)))

        let client = makeClient()
        let (zones, info) = try await Pagination.paginate([Zone].self, client: client) { page in
            CloudflareRequest(path: "/zones", query: [URLQueryItem(name: "page", value: "\(page)")])
        }
        XCTAssertEqual(zones.map(\.id), ["z1", "z2", "z3"])
        XCTAssertEqual(info?.totalPages, 2)
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertEqual(MockURLProtocol.requests[0].url?.query, "page=1")
        XCTAssertEqual(MockURLProtocol.requests[1].url?.query, "page=2")
    }

    func testCursorPaginationStopsWhenNotTruncated() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.enqueue(.init(data: Data("""
        {"success":true,"errors":[],"messages":[],"result":[{"key":"a.obj","size":10}],
         "result_info":{"cursor":"NEXT","is_truncated":true}}
        """.utf8)))
        MockURLProtocol.enqueue(.init(data: Data("""
        {"success":true,"errors":[],"messages":[],"result":[{"key":"b.obj","size":20}],
         "result_info":{"is_truncated":false}}
        """.utf8)))

        let client = makeClient()
        let objects = try await Pagination.paginateCursor([R2Object].self, client: client) { cursor in
            var query: [URLQueryItem] = []
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            return CloudflareRequest(path: "/r2/objects", query: query)
        }
        XCTAssertEqual(objects.map(\.key), ["a.obj", "b.obj"])
        XCTAssertEqual(MockURLProtocol.requests.count, 2)
        XCTAssertEqual(MockURLProtocol.requests[1].url?.query, "cursor=NEXT")
    }
}
