import Foundation

/// Token permission surface (14 capabilities), mirrored from the RN probe set.
nonisolated struct Permissions: Sendable, Equatable {
    var user = false
    var accounts = false
    var zones = false
    var dns = false
    var ssl = false
    var firewall = false
    var cache = false
    var pageRules = false
    var analytics = false
    var workers = false
    var kv = false
    var r2 = false
    var pages = false
    var d1 = false

    /// Permission names for UI display ("token lacks X").
    static let displayNames: [String] = [
        "User", "Accounts", "Zones", "DNS", "SSL", "Firewall", "Cache",
        "Page Rules", "Analytics", "Workers", "KV", "R2", "Pages", "D1",
    ]
}

/// Probes the API with per_page=1 reads; errors map to false (RN `probePermissions` parity).
nonisolated struct PermissionProber {
    let client: CloudflareClient

    /// Runs all probes concurrently; individual failures count as "no permission".
    func probe(accountId: String, zoneId: String) async -> Permissions {
        let perPage = [URLQueryItem(name: "per_page", value: "1")]

        // Permission checks intentionally decode into JSONValue rather than feature DTOs.
        // Authorization must not become false merely because Cloudflare adds a new field,
        // DNS record type, or nested response shape that the feature model does not know yet.
        async let user: Bool = probeAccess(CloudflareRequest(path: "/user"))
        async let accounts: Bool = probeAccess(CloudflareRequest(path: "/accounts", query: perPage))
        async let zones: Bool = probeAccess(CloudflareRequest(path: "/zones", query: perPage))
        async let dns: Bool = probeAccess(CloudflareRequest(path: "/zones/\(zoneId)/dns_records", query: perPage))
        async let ssl: Bool = probeAccess(CloudflareRequest(path: "/zones/\(zoneId)/settings/ssl"))
        async let firewall: Bool = probeAccess(CloudflareRequest(path: "/zones/\(zoneId)/firewall/rules", query: perPage))
        async let cache: Bool = probeAccess(CloudflareRequest(path: "/zones/\(zoneId)/settings/cache_level"))
        async let pageRules: Bool = probeAccess(CloudflareRequest(path: "/zones/\(zoneId)/pagerules", query: perPage))
        async let analytics: Bool = probeAnalytics()
        async let workers: Bool = probeAccess(CloudflareRequest(path: "/accounts/\(accountId)/workers/scripts"))
        async let kv: Bool = probeAccess(CloudflareRequest(path: "/accounts/\(accountId)/storage/kv/namespaces", query: perPage))
        async let r2: Bool = probeAccess(CloudflareRequest(path: "/accounts/\(accountId)/r2/buckets"))
        async let pages: Bool = probeAccess(CloudflareRequest(path: "/accounts/\(accountId)/pages/projects"))
        async let d1: Bool = probeAccess(CloudflareRequest(path: "/accounts/\(accountId)/d1/database"))

        var p = Permissions()
        p.user = await user
        p.accounts = await accounts
        p.zones = await zones
        p.dns = await dns
        p.ssl = await ssl
        p.firewall = await firewall
        p.cache = await cache
        p.pageRules = await pageRules
        p.analytics = await analytics
        p.workers = await workers
        p.kv = await kv
        p.r2 = await r2
        p.pages = await pages
        p.d1 = await d1
        return p
    }

    /// Minimal GraphQL query as the analytics permission probe.
    private func probeAnalytics() async -> Bool {
        struct ProbeResponse: Decodable {}
        do {
            _ = try await client.graphql(query: "{ viewer { zones { zoneTag } } }") as ProbeResponse
            return true
        } catch {
            return false
        }
    }

    /// Tests authorization using a schema-tolerant result. Internal for regression tests.
    func probeAccess(_ request: CloudflareRequest) async -> Bool {
        do {
            let _: CloudflareResponse<JSONValue> = try await client.send(request)
            return true
        } catch {
            return false
        }
    }
}
