import Foundation

/// Email routing and audit log endpoints.
nonisolated extension CloudflareEndpoint {
    // MARK: - Email routing (zone-scoped)

    static func emailRoutingSettings(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/email/routing")
    }

    static func enableEmailRouting(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/email/routing/enable", method: .post)
    }

    static func disableEmailRouting(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/email/routing/disable", method: .post)
    }

    static func emailRoutingDNS(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/email/routing/dns")
    }

    static func emailRules(zoneId: String, page: Int = 1) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/email/routing/rules", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "50"),
        ])
    }

    static func createEmailRule(zoneId: String, rule: EmailRoutingRule) throws -> CloudflareRequest {
        try CloudflareRequest.json(rule, path: "/zones/\(zoneId)/email/routing/rules", method: .post)
    }

    static func updateEmailRule(zoneId: String, ruleId: String, rule: EmailRoutingRule) throws -> CloudflareRequest {
        try CloudflareRequest.json(rule, path: "/zones/\(zoneId)/email/routing/rules/\(ruleId)", method: .put)
    }

    static func deleteEmailRule(zoneId: String, ruleId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/email/routing/rules/\(ruleId)", method: .delete)
    }

    static func catchAllRule(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/email/routing/rules/catch_all")
    }

    static func updateCatchAllRule(zoneId: String, rule: EmailRoutingRule) throws -> CloudflareRequest {
        try CloudflareRequest.json(rule, path: "/zones/\(zoneId)/email/routing/rules/catch_all", method: .put)
    }

    // MARK: - Destination addresses (account-scoped)

    static func destinationAddresses(accountId: String, page: Int = 1) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/email/routing/addresses", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "50"),
        ])
    }

    static func addDestinationAddress(accountId: String, email: String) throws -> CloudflareRequest {
        struct Body: Encodable { let email: String }
        return try CloudflareRequest.json(Body(email: email), path: "/accounts/\(accountId)/email/routing/addresses", method: .post)
    }

    static func deleteDestinationAddress(accountId: String, addressId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/email/routing/addresses/\(addressId)", method: .delete)
    }

    // MARK: - Audit logs (account-scoped)

    static func auditLogs(accountId: String, page: Int = 1) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/audit_logs", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "direction", value: "desc"),
        ])
    }
}

/// Rule payload for create/update (matcher/actions shape; multi-destination = value array).
nonisolated struct EmailRoutingRule: Codable, Sendable, Identifiable, Equatable {
    var id: String?
    var name: String?
    var enabled: Bool
    var priority: Int
    var matchers: [Matcher]
    var actions: [Action]

    /// Cloudflare only matches on the recipient — field is always "to".
    struct Matcher: Codable, Sendable, Equatable {
        var type: String  // "all" | "literal"
        var field: String?
        var value: String?

        static func literal(_ address: String) -> Matcher {
            Matcher(type: "literal", field: "to", value: address)
        }

        static func catchAll() -> Matcher {
            Matcher(type: "all", field: "to", value: nil)
        }
    }

    /// forward → value = verified destinations; worker → script names; drop → empty.
    struct Action: Codable, Sendable, Equatable {
        var type: String
        var value: [String]

        static func forward(_ destinations: [String]) -> Action {
            Action(type: "forward", value: destinations)
        }

        static func worker(_ script: String) -> Action {
            Action(type: "worker", value: [script])
        }

        static func drop() -> Action {
            Action(type: "drop", value: [])
        }
    }
}

/// One MX/TXT record Cloudflare needs in the zone for routing to work.
nonisolated struct EmailRoutingDnsRecord: Codable, Sendable {
    let type: String
    let name: String
    let content: String
    let priority: Int?
    let ttl: Int?
}
