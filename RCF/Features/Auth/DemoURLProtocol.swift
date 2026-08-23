import Foundation

/// URLProtocol serving canned Cloudflare API responses for the in-app demo.
/// Isolated on purpose: deleting this file + `AuthViewModel.startDemo()` +
/// the login button removes demo mode entirely.
///
/// GETs return realistic fixtures for the main flows; unknown paths fall back
/// to an empty success envelope so screens render empty instead of erroring.
/// Mutations return success.
nonisolated final class DemoURLProtocol: URLProtocol {
    nonisolated static let demoZoneId = "demo-zone-1"
    nonisolated static let demoZone2Id = "demo-zone-2"
    nonisolated static let demoAccountId = "demo-account"

    override class func canInit(with request: URLRequest) -> Bool {
        // Intercept only Cloudflare API traffic; everything else passes through.
        (request.url?.host ?? "").hasSuffix("cloudflare.com")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return fail() }
        let method = (request.httpMethod ?? "GET").uppercased()
        let path = url.path // e.g. /client/v4/zones/demo-zone-1/dns_records

        guard let data = DemoFixtures.response(method: method, path: path, query: url.query ?? "") else {
            return fail()
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func fail() {
        client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
    }
}

/// Fixture router. Path matching is prefix/segment based — zone ids in paths
/// are ignored so any zone flows show the same demo data.
nonisolated enum DemoFixtures {
    static func response(method: String, path: String, query: String) -> Data? {
        // GraphQL (analytics): any POST → raw GraphQL document (not an envelope).
        if path.hasSuffix("/graphql"), method == "POST" {
            return Data("""
            {"data":{"viewer":{"zones":[{"sum":{"requests":48213,"cachedRequests":39420,"bytes":987234567,"cachedBytes":912345678,"threats":132,"pageViews":22140},"uniq":{"uniques":8412}}]}}}
            """.utf8)
        }

        // Mutations → success envelope.
        switch method {
        case "POST", "PUT", "PATCH", "DELETE":
            if path.hasSuffix("/purge_cache") {
                return Data("""
                {"result":{"id":"purge-demo"},"success":true,"errors":[],"messages":[]}
                """.utf8)
            }
            return Data("""
            {"result":null,"success":true,"errors":[],"messages":[]}
            """.utf8)
        default: break
        }

        // GET routes.
        let segments = path.split(separator: "/").map(String.init) // ["client","v4",...]

        func seg(_ i: Int) -> String? { i < segments.count ? segments[i] : nil }

        // /client/v4/...
        if seg(0) == "client", seg(1) == "v4" {
            switch seg(2) {
            case "user":
                if seg(3) == "tokens", seg(4) == "verify" {
                    return envelope(#"{"id":"demo-token","status":"active"}"#)
                }
                return envelope(#"{"id":"u1","email":"demo@8ugust.dev","first_name":"Demo","last_name":"User"}"#)
            case "accounts":
                if seg(3) == nil {
                    return envelope("[{\"id\":\"\(DemoURLProtocol.demoAccountId)\",\"name\":\"August Labs\"}]")
                }
                return emptyList()
            case "zones":
                return zoneRoutes(seg)
            default:
                return emptyList()
            }
        }
        return emptyList()
    }

    private static func zoneRoutes(_ seg: (Int) -> String?) -> Data? {
        // /zones (list)
        guard let zoneId = seg(3) else {
            return Data(zonesJSON.utf8)
        }
        let tail = seg(4)
        switch tail {
        case nil:
            return envelope(zoneJSON(id: zoneId))
        case "settings":
            if let name = seg(5) {
                return envelope(settingJSON(name: name))
            }
            return Data(("{\"result\":[" + [settingJSON(name: "ssl"), settingJSON(name: "always_use_https"), settingJSON(name: "min_tls_version"), settingJSON(name: "development_mode"), settingJSON(name: "cache_level")].joined(separator: ",") + "],\"success\":true,\"errors\":[],\"messages\":[]}").utf8)
        case "dns_records":
            if seg(5) == "export" {
                let text = ";; Demo zone export\nexample.com. 1 IN A 192.0.2.1\n"
                return Data(text.utf8)
            }
            return Data(dnsRecordsJSON.utf8)
        case "analytics", "analytics_dashboard":
            return Data(dashboardJSON.utf8)
        case "firewall", "rulesets", "pagerules", "ssl", "argo":
            return emptyList()
        case "email":
            return envelope(#"{"enabled":false,"name":"demo","tag":"demo","status":"unconfigured"}"#)
        case "dnssec":
            return envelope(#"{"status":"active"}"#)
        default:
            return emptyList()
        }
    }

    // MARK: - Payloads

    static let zonesJSON = """
    {"result":[\(zoneJSON(id: DemoURLProtocol.demoZoneId, name: "8ugust.dev", status: "active", plan: "Pro")),\(zoneJSON(id: DemoURLProtocol.demoZone2Id, name: "staging.8ugust.dev", status: "pending", plan: "Free"))],"result_info":{"page":1,"per_page":50,"count":2,"total_count":2,"total_pages":1},"success":true,"errors":[],"messages":[]}
    """

    static func zoneJSON(id: String, name: String = "8ugust.dev", status: String = "active", plan: String = "Pro") -> String {
        let planPrice = plan == "Pro" ? "20" : "0"
        return """
        {"id":"\(id)","name":"\(name)","status":"\(status)","paused":false,"type":"full","development_mode":0,
         "name_servers":["aria.ns.cloudflare.com","bob.ns.cloudflare.com"],
         "modified_on":"2026-08-01T00:00:00Z","created_on":"2026-01-01T00:00:00Z","activated_on":"2026-01-02T00:00:00Z",
         "plan":{"id":"p1","name":"\(plan)","price":\(planPrice),"currency":"USD","frequency":"","is_subscribed":true},
         "account":{"id":"\(DemoURLProtocol.demoAccountId)","name":"August Labs"}}
        """
    }

    static let dnsRecordsJSON = """
    {"result":[
      {"id":"r1","zone_id":"\(DemoURLProtocol.demoZoneId)","zone_name":"8ugust.dev","name":"8ugust.dev","type":"A","content":"192.0.2.1","proxiable":true,"proxied":true,"ttl":1,"locked":false,"comment":null,"tags":[],"created_on":"2026-01-01T00:00:00Z","modified_on":"2026-08-01T00:00:00Z"},
      {"id":"r2","zone_id":"\(DemoURLProtocol.demoZoneId)","zone_name":"8ugust.dev","name":"www","type":"CNAME","content":"8ugust.dev","proxiable":true,"proxied":true,"ttl":1,"locked":false,"comment":null,"tags":[],"created_on":"2026-01-01T00:00:00Z","modified_on":null},
      {"id":"r3","zone_id":"\(DemoURLProtocol.demoZoneId)","zone_name":"8ugust.dev","name":"api","type":"A","content":"192.0.2.10","proxiable":true,"proxied":false,"ttl":300,"locked":false,"comment":"origin","tags":[],"created_on":null,"modified_on":null},
      {"id":"r4","zone_id":"\(DemoURLProtocol.demoZoneId)","zone_name":"8ugust.dev","name":"@","type":"MX","content":"route1.mx.cloudflare.net","proxiable":false,"proxied":false,"ttl":3600,"locked":false,"priority":13,"tags":[],"created_on":null,"modified_on":null},
      {"id":"r5","zone_id":"\(DemoURLProtocol.demoZoneId)","zone_name":"8ugust.dev","name":"_dmarc","type":"TXT","content":"v=DMARC1; p=quarantine; rua=mailto:dmarc@8ugust.dev","proxiable":false,"proxied":false,"ttl":3600,"locked":false,"tags":[],"created_on":null,"modified_on":null}
    ],"result_info":{"page":1,"per_page":50,"count":5,"total_count":5,"total_pages":1},"success":true,"errors":[],"messages":[]}
    """

    static func settingJSON(name: String) -> String {
        let value: String
        switch name {
        case "ssl": value = "\"flexible\""
        case "always_use_https": value = "\"on\""
        case "min_tls_version": value = "\"1.2\""
        case "development_mode": value = "false"
        case "cache_level": value = "\"aggressive\""
        case "security_level": value = "\"medium\""
        case "brotli", "always_online", "http2", "http3", "0rtt", "polish", "webp": value = "\"on\""
        case "browser_cache_ttl": value = "14400"
        default: value = "\"off\""
        }
        return """
        {"id":"\(name)","value":\(value),"editable":true,"modified_on":"2026-08-01T00:00:00Z"}
        """
    }

    static let dashboardJSON = """
    {"result":{"totals":{"requests":{"all":48213,"cached":39420,"uncached":8793},"bandwidth":{"all":987234567,"cached":912345678,"uncached":74888889},"threats":{"all":132},"pageviews":{"all":22140},"uniques":{"all":8412}},"requests":[{"since":"2026-08-22T00:00:00Z","until":"2026-08-23T00:00:00Z","requests":{"all":4200,"cached":3600,"uncached":600},"bandwidth":{"all":9876543,"cached":9123456,"uncached":753087},"threats":{"all":11},"pageviews":{"all":2000},"uniques":{"all":700}}]},"success":true,"errors":[],"messages":[]}
    """

    // MARK: - Envelope helpers

    static func envelope(_ resultJSON: String) -> Data {
        // resultJSON already carries its own wrapper or is a raw result — wrap raw ones.
        Data("""
        {"result":\(resultJSON),"success":true,"errors":[],"messages":[]}
        """.utf8)
    }

    static func emptyList() -> Data {
        Data("""
        {"result":[],"result_info":{"page":1,"per_page":50,"count":0,"total_count":0,"total_pages":1},"success":true,"errors":[],"messages":[]}
        """.utf8)
    }
}
