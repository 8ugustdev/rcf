import XCTest
@testable import RCF

/// CloudflareClient behavior: auth headers, envelope decode, errors, throttle, multipart, pagination.
final class RCFClientTests: XCTestCase {
    private func makeClient(auth: AuthConfig) -> CloudflareClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return CloudflareClient(auth: auth, session: URLSession(configuration: config))
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    // MARK: - Auth headers

    func testTokenAuthHeaderOnGet() async throws {
        let client = makeClient(auth: .token("secret-token-1234"))
        MockURLProtocol.enqueue(.init(data: Data(#"{"success":true,"errors":[],"messages":[],"result":[]}"#.utf8)))
        let _: ([Zone], ResultInfo?) = try await client.sendList(CloudflareRequest(path: "/zones"))
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token-1234")
    }

    func testTokenWhitespaceStripped() async throws {
        let client = makeClient(auth: .token("  secret token \n"))
        MockURLProtocol.enqueue(.init(data: Data(#"{"success":true,"errors":[],"messages":[],"result":[]}"#.utf8)))
        let _: ([Zone], ResultInfo?) = try await client.sendList(CloudflareRequest(path: "/zones"))
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secrettoken")
    }

    func testGlobalKeyAuthHeaders() async throws {
        let client = makeClient(auth: .globalKey(email: "user@example.com", key: "gkey-abcdef"))
        MockURLProtocol.enqueue(.init(data: Data(#"{"success":true,"errors":[],"messages":[],"result":[]}"#.utf8)))
        let _: ([Zone], ResultInfo?) = try await client.sendList(CloudflareRequest(path: "/zones"))
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth-Email"), "user@example.com")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Auth-Key"), "gkey-abcdef")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testAuthHeadersOnGraphQLAndRaw() async throws {
        let client = makeClient(auth: .token("tok-graphql"))

        // GraphQL
        struct Viewer: Decodable { let zones: [ZoneTag]
            struct ZoneTag: Decodable { let zoneTag: String } }
        MockURLProtocol.enqueue(.init(data: Data(#"{"data":{"zones":[{"zoneTag":"abc"}]}}"#.utf8)))
        let viewer = try await client.graphql(query: "{ viewer { zones { zoneTag } } }") as Viewer
        XCTAssertEqual(viewer.zones.first?.zoneTag, "abc")

        // Raw
        MockURLProtocol.enqueue(.init(statusCode: 200, data: Data("1.2.3.4 IN A".utf8)))
        let (rawData, _) = try await client.sendRaw(CloudflareRequest(path: "/zones/z/dns_records/export"))
        XCTAssertEqual(String(decoding: rawData, as: UTF8.self), "1.2.3.4 IN A")

        let graphQLRequest = MockURLProtocol.requests[0]
        XCTAssertEqual(graphQLRequest.value(forHTTPHeaderField: "Authorization"), "Bearer tok-graphql")
        XCTAssertEqual(graphQLRequest.url?.absoluteString, CloudflareClient.graphqlURL.absoluteString)
        let rawRequest = MockURLProtocol.requests[1]
        XCTAssertEqual(rawRequest.value(forHTTPHeaderField: "Authorization"), "Bearer tok-graphql")
    }

    // MARK: - Envelope and errors

    func testEnvelopeDecodeSuccess() async throws {
        let client = makeClient(auth: .token("t"))
        let json = """
        {"success":true,"errors":[],"messages":[],
         "result":[{"id":"z1","name":"example.com","status":"active","paused":false,"type":"full",
           "development_mode":0,"name_servers":["ns1.cloudflare.com"],
           "modified_on":null,"created_on":null,"activated_on":null,
           "plan":{"id":"p","name":"Free","price":0,"currency":"USD","frequency":"","is_subscribed":false},
           "account":{"id":"a1","name":"My Account"}}],
         "result_info":{"page":1,"per_page":50,"count":1,"total_count":1,"total_pages":1}}
        """
        MockURLProtocol.enqueue(.init(data: Data(json.utf8)))
        let (zones, info): ([Zone], ResultInfo?) = try await client.sendList(CloudflareRequest(path: "/zones"))
        XCTAssertEqual(zones.first?.name, "example.com")
        XCTAssertEqual(info?.totalPages, 1)
    }

    func testAPIErrorThrows() async {
        let client = makeClient(auth: .token("t"))
        let json = #"{"success":false,"errors":[{"code":9109,"message":"Unauthorized to access requested resource"}],"messages":[],"result":null}"#
        MockURLProtocol.enqueue(.init(data: Data(json.utf8)))
        do {
            let _: ([Zone], ResultInfo?) = try await client.sendList(CloudflareRequest(path: "/zones"))
            XCTFail("expected throw")
        } catch let error as CloudflareError {
            guard case let .api(code, message, _) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(code, 9109)
            XCTAssertTrue(message.contains("Unauthorized"))
            XCTAssertTrue(error.isPermissionDenied)
        } catch {
            XCTFail("unexpected error type")
        }
    }

    func testRateLimitedFrom429Header() async {
        let client = makeClient(auth: .token("t"))
        MockURLProtocol.enqueue(.init(statusCode: 429, headers: ["Retry-After": "37"], data: Data("{}".utf8)))
        do {
            let _: ([Zone], ResultInfo?) = try await client.sendList(CloudflareRequest(path: "/zones"))
            XCTFail("expected throw")
        } catch let error as CloudflareError {
            guard case let .rateLimited(retryAfter) = error else { return XCTFail("wrong error \(error)") }
            XCTAssertEqual(retryAfter, 37)
        } catch {
            XCTFail("unexpected error type")
        }
    }

    func testUnauthorizedFrom401() async {
        let client = makeClient(auth: .token("bad"))
        MockURLProtocol.enqueue(.init(statusCode: 401, data: Data("{}".utf8)))
        do {
            let _: ([Zone], ResultInfo?) = try await client.sendList(CloudflareRequest(path: "/zones"))
            XCTFail("expected throw")
        } catch let error as CloudflareError {
            guard case .unauthorized = error else { return XCTFail("wrong error \(error)") }
        } catch {
            XCTFail("unexpected error type")
        }
    }

    // MARK: - Bodies

    func testMultipartBodyStructure() {
        var body = MultipartBody(boundary: "BOUNDARY")
        body.field(name: "value", value: "hello world")
        body.file(name: "file", filename: "zone.txt", contentType: "text/plain", data: Data("A records".utf8))
        let encoded = String(decoding: body.encoded(), as: UTF8.self)
        XCTAssertTrue(encoded.contains("--BOUNDARY\r\n"))
        XCTAssertTrue(encoded.contains("Content-Disposition: form-data; name=\"value\"\r\n\r\nhello world\r\n"))
        XCTAssertTrue(encoded.contains("Content-Disposition: form-data; name=\"file\"; filename=\"zone.txt\""))
        XCTAssertTrue(encoded.contains("Content-Type: text/plain"))
        XCTAssertTrue(encoded.hasSuffix("--BOUNDARY--\r\n"))
    }

    func testRawTextBodyAndContentType() async throws {
        let client = makeClient(auth: .token("t"))
        MockURLProtocol.enqueue(.init(data: Data("{}".utf8)))
        _ = try await client.sendRaw(CloudflareRequest.text("payload", contentType: "text/plain", path: "/x", method: .put))
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/plain")
        XCTAssertEqual(request.httpBodyStream.map { _ in () } != nil || request.httpBody != nil, true)
    }

    func testMultipartRequestHeaderAndBody() async throws {
        let client = makeClient(auth: .token("t"))
        var multipart = MultipartBody(boundary: "B1")
        multipart.field(name: "value", value: "v")
        MockURLProtocol.enqueue(.init(data: Data("{}".utf8)))
        _ = try await client.sendRaw(CloudflareRequest(path: "/kv", method: .put, body: .multipart(multipart)))
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=B1")
    }

    // MARK: - Local throttle

    func testLocalThrottleRejectsWhenBudgetExhausted() async {
        let tracker = RateLimitTracker(limit: 2, window: 300)
        try? await tracker.acquire()
        try? await tracker.acquire()
        await tracker.record()
        await tracker.record()
        do {
            try await tracker.acquire()
            XCTFail("expected throttle")
        } catch let error as CloudflareError {
            guard case .throttled = error else { return XCTFail("wrong error") }
        } catch {
            XCTFail("unexpected error type")
        }
    }
}
