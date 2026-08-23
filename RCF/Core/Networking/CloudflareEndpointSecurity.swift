import Foundation

/// SSL, firewall, page rules, and analytics endpoints.
nonisolated extension CloudflareEndpoint {
    static let wafCustomPhase = "http_request_firewall_custom"

    // MARK: - SSL

    static func sslCertificatePack(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/ssl/certificate_packs", query: [URLQueryItem(name: "status", value: "active")])
    }

    // MARK: - Firewall (legacy)

    static func firewallRules(zoneId: String, page: Int = 1) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/firewall/rules", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "50"),
        ])
    }

    static func updateFirewallRule(zoneId: String, ruleId: String, paused: Bool) throws -> CloudflareRequest {
        struct Body: Encodable { let paused: Bool }
        return try CloudflareRequest.json(Body(paused: paused), path: "/zones/\(zoneId)/firewall/rules/\(ruleId)", method: .put)
    }

    static func deleteFirewallRule(zoneId: String, ruleId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/firewall/rules/\(ruleId)", method: .delete)
    }

    // MARK: - IP access rules

    static func ipAccessRules(zoneId: String, page: Int = 1) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/firewall/access_rules/rules", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "50"),
        ])
    }

    static func createIPAccessRule(zoneId: String, mode: String, targetKind: String, value: String, notes: String?) throws -> CloudflareRequest {
        struct Body: Encodable {
            let mode: String
            let configuration: Configuration
            let notes: String?
            struct Configuration: Encodable {
                let target: String
                let value: String
            }
        }
        return try CloudflareRequest.json(
            Body(mode: mode, configuration: .init(target: configurationTarget(targetKind), value: value), notes: notes),
            path: "/zones/\(zoneId)/firewall/access_rules/rules",
            method: .post
        )
    }

    /// Maps UI target kind → API configuration.target.
    private static func configurationTarget(_ kind: String) -> String {
        switch kind {
        case "ip_range": "ip_range"
        case "country", "asn", "continent": kind
        default: "ip"
        }
    }

    static func updateIPAccessRule(zoneId: String, ruleId: String, mode: String, notes: String?) throws -> CloudflareRequest {
        struct Body: Encodable {
            let mode: String
            let notes: String?
        }
        return try CloudflareRequest.json(Body(mode: mode, notes: notes), path: "/zones/\(zoneId)/firewall/access_rules/rules/\(ruleId)", method: .patch)
    }

    static func deleteIPAccessRule(zoneId: String, ruleId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/firewall/access_rules/rules/\(ruleId)", method: .delete)
    }

    // MARK: - WAF custom rules (rulesets)

    static func wafCustomEntrypoint(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/rulesets/phases/\(wafCustomPhase)/entrypoint")
    }

    /// Creates the phase entrypoint — virgin zones 404 on the rules endpoints until this exists.
    static func createWAFEntrypoint(zoneId: String) throws -> CloudflareRequest {
        struct Body: Encodable {
            let name: String
            let kind: String
            let phase: String
            let rules: [String]
        }
        return try CloudflareRequest.json(
            Body(name: "Custom rules", kind: "zone", phase: wafCustomPhase, rules: []),
            path: "/zones/\(zoneId)/rulesets/phases/\(wafCustomPhase)/entrypoint",
            method: .put
        )
    }

    static func createRulesetRule(zoneId: String, rulesetId: String, action: String, expression: String, description: String?, enabled: Bool) throws -> CloudflareRequest {
        struct Body: Encodable {
            let action: String
            let expression: String
            let description: String?
            let enabled: Bool
        }
        return try CloudflareRequest.json(
            Body(action: action, expression: expression, description: description, enabled: enabled),
            path: "/zones/\(zoneId)/rulesets/\(rulesetId)/rules",
            method: .post
        )
    }

    static func updateRulesetRule(zoneId: String, rulesetId: String, ruleId: String, action: String? = nil, expression: String? = nil, description: String? = nil, enabled: Bool? = nil) throws -> CloudflareRequest {
        struct Body: Encodable {
            let action: String?
            let expression: String?
            let description: String?
            let enabled: Bool?
        }
        return try CloudflareRequest.json(
            Body(action: action, expression: expression, description: description, enabled: enabled),
            path: "/zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)",
            method: .patch
        )
    }

    static func deleteRulesetRule(zoneId: String, rulesetId: String, ruleId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/rulesets/\(rulesetId)/rules/\(ruleId)", method: .delete)
    }

    // MARK: - Page rules

    static func pageRules(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/pagerules", query: [URLQueryItem(name: "status", value: "active,disabled")])
    }

    static func deletePageRule(zoneId: String, ruleId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/pagerules/\(ruleId)", method: .delete)
    }
}

/// Active certificate pack (verification status list).
nonisolated struct CertificatePack: Codable, Sendable, Identifiable {
    let id: String
    let status: String
    let hosts: [String]?
    let certificateAuthority: String?
    let validity: Validity?
    let validationRecords: [ValidationRecord]?

    struct Validity: Codable, Sendable {
        let startsOn: String?
        let expiresOn: String?

        enum CodingKeys: String, CodingKey {
            case startsOn = "starts_on"
            case expiresOn = "expires_on"
        }
    }

    struct ValidationRecord: Codable, Sendable {
        let status: String?
        let type: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, status, hosts, validity
        case certificateAuthority = "certificate_authority"
        case validationRecords = "validation_records"
    }
}

/// Result wrapper for R2-style nested list (`result.buckets`).
nonisolated struct CertificatePackList: Codable, Sendable {
    let result: [CertificatePack]?
}
/// Aggregated zone analytics (RN `GraphQLAnalytics` parity).
nonisolated struct GraphQLAnalytics: Sendable, Equatable {
    struct Series: Sendable, Equatable {
        let date: String
        let requests: Int
        let cachedRequests: Int
        let bytes: Int
        let cachedBytes: Int
        let threats: Int
        let pageViews: Int
        let uniques: Int
    }

    var requestsTotal = 0
    var requestsCached = 0
    var bytesTotal = 0
    var bytesCached = 0
    var threatsTotal = 0
    var pageviewsTotal = 0
    var uniquesTotal = 0
    var timeseries: [Series] = []
}

nonisolated extension CloudflareClient {
    /// Fetches and aggregates zone analytics via GraphQL (RN `getZoneAnalytics` parity).
    func zoneAnalytics(zoneId: String, days: Int) async throws -> GraphQLAnalytics {
        struct Response: Decodable {
            let viewer: Viewer
            struct Viewer: Decodable {
                let zones: [ZoneNode]
            }
            struct ZoneNode: Decodable {
                let httpRequests1dGroups: [Group]?
            }
            struct Group: Decodable {
                let dimensions: Dimensions
                let sum: Sum
                let uniq: Uniq
                struct Dimensions: Decodable { let date: String }
                struct Sum: Decodable {
                    let requests: Int
                    let cachedRequests: Int
                    let bytes: Int
                    let cachedBytes: Int
                    let pageViews: Int
                    let threats: Int
                }
                struct Uniq: Decodable { let uniques: Int }
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let end = Date.now
        let start = end.addingTimeInterval(-Double(days) * 86400)
        let query = """
        { viewer { zones(filter: { zoneTag: "\(zoneId)" }) {
          httpRequests1dGroups(limit: 31, filter: { date_geq: "\(formatter.string(from: start))", date_leq: "\(formatter.string(from: end))" }, orderBy: [date_ASC]) {
            dimensions { date }
            sum { requests cachedRequests bytes cachedBytes pageViews threats }
            uniq { uniques }
          }
        } } }
        """
        let response = try await graphql(query: query) as Response
        let groups = response.viewer.zones.first?.httpRequests1dGroups ?? []
        var analytics = GraphQLAnalytics()
        analytics.timeseries = groups.map { group in
            GraphQLAnalytics.Series(
                date: group.dimensions.date,
                requests: group.sum.requests,
                cachedRequests: group.sum.cachedRequests,
                bytes: group.sum.bytes,
                cachedBytes: group.sum.cachedBytes,
                threats: group.sum.threats,
                pageViews: group.sum.pageViews,
                uniques: group.uniq.uniques
            )
        }
        for series in analytics.timeseries {
            analytics.requestsTotal += series.requests
            analytics.requestsCached += series.cachedRequests
            analytics.bytesTotal += series.bytes
            analytics.bytesCached += series.cachedBytes
            analytics.threatsTotal += series.threats
            analytics.pageviewsTotal += series.pageViews
            analytics.uniquesTotal += series.uniques
        }
        return analytics
    }
}
