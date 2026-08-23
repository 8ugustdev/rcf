import XCTest
@testable import RCF

/// Platform endpoints: R2 nested envelope, cursor, D1 quoting, KV multipart.
final class PlatformTests: XCTestCase {
    func testR2NestedBucketEnvelopeDecode() throws {
        let json = """
        {"success":true,"errors":[],"messages":[],
         "result":{"buckets":[{"name":"media","creation_date":"2026-01-01T00:00:00Z"}]}}
        """
        let decoded = try JSONDecoder().decode(CloudflareResponse<R2BucketList>.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.result?.buckets.first?.name, "media")
    }

    func testKVValueWriteMultipartShape() {
        let request = CloudflareEndpoint.kvValueWrite(accountId: "a1", nsId: "ns1", key: "config", value: "{\"x\":1}")
        XCTAssertEqual(request.path, "/accounts/a1/storage/kv/namespaces/ns1/values/config")
        XCTAssertEqual(request.method, .put)
        guard case let .multipart(body) = request.body else { return XCTFail("expected multipart") }
        let encoded = String(decoding: body.encoded(), as: UTF8.self)
        XCTAssertTrue(encoded.contains("name=\"value\""))
        XCTAssertTrue(encoded.contains("{\"x\":1}"))
    }

    func testKVKeyPathEncoding() {
        let request = CloudflareEndpoint.kvValueRead(accountId: "a", nsId: "n", key: "nested/key with space")
        XCTAssertTrue(request.path.contains("nested%2Fkey%20with%20space"))
    }

    func testD1IdentifierQuoting() {
        XCTAssertEqual(CloudflareClient.quoteIdentifier("users"), "users")
        XCTAssertEqual(CloudflareClient.quoteIdentifier("my\"table"), "my\"\"table")
    }

    func testD1RowsSQL() {
        let sql = "SELECT * FROM \"\(CloudflareClient.quoteIdentifier("ord\"ers"))\" LIMIT 50 OFFSET 100"
        XCTAssertEqual(sql, "SELECT * FROM \"ord\"\"ers\" LIMIT 50 OFFSET 100")
    }

    func testR2ObjectsCursorAndPrefixQuery() {
        let request = CloudflareEndpoint.r2Objects(accountId: "a", bucket: "b", cursor: "NEXT", prefix: "img/")
        XCTAssertEqual(request.path, "/accounts/a/r2/buckets/b/objects")
        let names = request.query.map(\.name)
        XCTAssertTrue(names.contains("cursor"))
        XCTAssertTrue(names.contains("prefix"))
    }

    func testD1QueryResultDecode() throws {
        let json = """
        {"success":true,"errors":[],"messages":[],
         "result":[{"results":[{"id":1,"name":"alice"}],"success":true,
                    "meta":{"duration":0.01,"rows_read":2,"rows_written":0}}]}
        """
        let decoded = try JSONDecoder().decode(CloudflareResponse<[D1QueryResult.Result]>.self, from: Data(json.utf8))
        let first = try XCTUnwrap(decoded.result?.first)
        XCTAssertEqual(first.results?.count, 1)
        if case let .object(dict)? = first.results?.first {
            XCTAssertEqual(dict["name"]?.displayString, "alice")
        } else {
            XCTFail("expected object row")
        }
    }
}
