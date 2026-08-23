import XCTest
@testable import RCF

/// Analytics aggregation from GraphQL fixture + expression validation + WAF bootstrap.
final class SecurityTests: XCTestCase {
    private func makeClient() -> CloudflareClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return CloudflareClient(auth: .token("t"), session: URLSession(configuration: config))
    }

    func testAnalyticsAggregationFromGraphQLFixture() async throws {
        MockURLProtocol.reset()
        let fixture = """
        {"data":{"viewer":{"zones":[{"httpRequests1dGroups":[
          {"dimensions":{"date":"2026-08-21"},"sum":{"requests":100,"cachedRequests":60,"bytes":1000,"cachedBytes":500,"pageViews":40,"threats":2},"uniq":{"uniques":30}},
          {"dimensions":{"date":"2026-08-22"},"sum":{"requests":50,"cachedRequests":30,"bytes":2000,"cachedBytes":1500,"pageViews":20,"threats":0},"uniq":{"uniques":10}}
        ]}]}}}
        """
        MockURLProtocol.enqueue(.init(data: Data(fixture.utf8)))
        let client = makeClient()
        let analytics = try await client.zoneAnalytics(zoneId: "z1", days: 7)
        XCTAssertEqual(analytics.timeseries.count, 2)
        XCTAssertEqual(analytics.requestsTotal, 150)
        XCTAssertEqual(analytics.requestsCached, 90)
        XCTAssertEqual(analytics.bytesTotal, 3000)
        XCTAssertEqual(analytics.bytesCached, 2000)
        XCTAssertEqual(analytics.threatsTotal, 2)
        XCTAssertEqual(analytics.pageviewsTotal, 60)
        XCTAssertEqual(analytics.uniquesTotal, 40)
    }

    func testWAFVirginZone404ThenBootstrap() async throws {
        MockURLProtocol.reset()
        // 1st: entrypoint GET → 404 (virgin zone)
        MockURLProtocol.enqueue(.init(statusCode: 404, data: Data("{}".utf8)))
        // 2nd: entrypoint PUT (bootstrap) → ruleset id
        let ruleset = """
        {"success":true,"errors":[],"messages":[],"result":{"id":"rs1","name":"Custom rules","kind":"zone","phase":"http_request_firewall_custom","rules":[]}}
        """
        MockURLProtocol.enqueue(.init(data: Data(ruleset.utf8)))
        // 3rd: create rule in ruleset
        MockURLProtocol.enqueue(.init(data: Data(ruleset.utf8)))

        let client = makeClient()

        // Mirror FirewallViewModel flow: load (404) → ensure ruleset (PUT) → create rule.
        var rulesetId: String?
        do {
            let _: CloudflareResponse<Ruleset> = try await client.send(CloudflareEndpoint.wafCustomEntrypoint(zoneId: "z1"))
            XCTFail("expected 404")
        } catch let error as CloudflareError {
            guard case let .http(status, _) = error, status == 404 else { return XCTFail("expected .http(404), got \(error)") }
        }

        let bootstrapped: CloudflareResponse<Ruleset> = try await client.send(try CloudflareEndpoint.createWAFEntrypoint(zoneId: "z1"))
        rulesetId = bootstrapped.result?.id
        XCTAssertEqual(rulesetId, "rs1")

        let _: CloudflareResponse<Ruleset> = try await client.send(
            try CloudflareEndpoint.createRulesetRule(zoneId: "z1", rulesetId: rulesetId!, action: "block", expression: "(http.request.uri.path contains \"/admin\")", description: "block admin", enabled: true)
        )

        // Verify request bodies: bootstrap + rule create.
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
        let bootstrapBody = String(decoding: MockURLProtocol.requests[1].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(bootstrapBody.contains("\"phase\":\"http_request_firewall_custom\""))
        XCTAssertTrue(bootstrapBody.contains("\"phase\":\"http_request_firewall_custom\""))
        let ruleBody = String(decoding: MockURLProtocol.requests[2].httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(ruleBody.contains("\"expression\"") && ruleBody.contains("/admin") && ruleBody.contains("\"action\":\"block\""))
    }

    func testExpressionValidator() {
        XCTAssertTrue(ExpressionValidator.isValid("(http.host eq \"example.com\")"))
        XCTAssertTrue(ExpressionValidator.isValid("(ip.src in {1.2.3.4 5.6.7.8})"))
        XCTAssertTrue(ExpressionValidator.isValid("((http.host eq \"a\") or (http.host eq \"b\"))"))
        XCTAssertFalse(ExpressionValidator.isValid("(http.host eq \"example.com\"")) // unbalanced paren
        XCTAssertFalse(ExpressionValidator.isValid("(http.host eq \"example)")) // unbalanced quote
        XCTAssertFalse(ExpressionValidator.isValid(")")) // early close
        XCTAssertTrue(ExpressionValidator.isValid("http.host eq \"a)b\"")) // paren inside quotes OK
    }

    func testIPAccessRuleBodyShape() throws {
        let request = try CloudflareEndpoint.createIPAccessRule(zoneId: "z1", mode: "block", targetKind: "country", value: "VN", notes: "spam")
        XCTAssertEqual(request.path, "/zones/z1/firewall/access_rules/rules")
        let body = String(decoding: (request.httpBodyData ?? Data()), as: UTF8.self)
        XCTAssertTrue(body.contains("\"target\":\"country\""))
        XCTAssertTrue(body.contains("\"value\":\"VN\""))
        XCTAssertTrue(body.contains("\"mode\":\"block\""))
    }

    func testPageRulesListEndpoint() {
        let request = CloudflareEndpoint.pageRules(zoneId: "z1")
        XCTAssertEqual(request.path, "/zones/z1/pagerules")
    }
}

extension CloudflareRequest {
    /// Body bytes regardless of kind (test helper).
    var httpBodyData: Data? {
        switch body {
        case .none: nil
        case let .json(data): data
        case let .raw(data, _): data
        case let .multipart(multipart): multipart.encoded()
        }
    }
}

/// Cloudflare reports missing entrypoint ruleset as envelope code 10073 (often HTTP 500).
@MainActor
final class FirewallNotFoundTests: XCTestCase {
    func testAPICode10073CountsAsNotFound() {
        let error = CloudflareError.api(code: 10073, message: "could not find entrypoint ruleset", errors: [])
        XCTAssertTrue(FirewallViewModel.isNotFound(error))
        XCTAssertTrue(FirewallViewModel.isNotFound(.http(status: 404, retryAfter: nil)))
        XCTAssertFalse(FirewallViewModel.isNotFound(.http(status: 500, retryAfter: nil)))
        XCTAssertFalse(FirewallViewModel.isNotFound(.api(code: 1000, message: "other", errors: [])))
    }

    func testAnyCodeWithEntrypointMessageCountsAsNotFound() {
        let error = CloudflareError.api(
            code: 10071,
            message: "could not find entrypoint ruleset in the http_request_firewall_custom phase",
            errors: []
        )
        XCTAssertTrue(FirewallViewModel.isNotFound(error))
    }
}
