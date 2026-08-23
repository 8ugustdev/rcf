import Foundation

/// Email routing, audit log, and GraphQL analytics DTOs.

// MARK: - Email routing

nonisolated struct EmailRoutingSettings: Codable, Sendable {
    let enabled: Bool
    let name: String?
    let tag: String?
    let skipWizard: Bool?
    let status: String
    let created: String?
    let modified: String?

    enum CodingKeys: String, CodingKey {
        case enabled, name, tag, status, created, modified
        case skipWizard = "skip_wizard"
    }
}

// EmailRoutingRule lives in CloudflareEndpointEmail.swift (full editor-capable model).

nonisolated struct EmailDestination: Codable, Sendable, Identifiable {
    let id: String?
    let email: String
    let verified: String?  // timestamp or null
    let created: String?
    let modified: String?
}

// MARK: - Audit logs

nonisolated struct AuditLogEntry: Codable, Sendable, Identifiable {
    let id: String
    let when: String
    let ip: String?
    let actorEmail: String?
    let actorType: String?
    let resourceName: String?
    let resourceType: String?
    let actionType: String?
    let metadata: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, when, ip
        case actorEmail = "actor.email"
        case actorType = "actor.type"
        case resourceName = "resource.name"
        case resourceType = "resource.type"
        case actionType = "action.type"
        case metadata
    }
}

// MARK: - GraphQL analytics

/// Requested by zone analytics dashboard (RN `ZoneAnalyticsDashboard` parity).
nonisolated struct ZoneAnalyticsDashboard: Codable, Sendable {
    let totals: Totals
    let timeseries: [Timeseries]

    struct Totals: Codable, Sendable {
        let requests: Requests
        let bandwidth: Bandwidth
        let threats: Threats
        let pageviews: Pageviews
        let uniques: Uniques

        struct Requests: Codable, Sendable { let all: Int; let cached: Int; let uncached: Int }
        struct Bandwidth: Codable, Sendable { let all: Int; let cached: Int; let uncached: Int }
        struct Threats: Codable, Sendable { let all: Int }
        struct Pageviews: Codable, Sendable { let all: Int }
        struct Uniques: Codable, Sendable { let all: Int }
    }

    struct Timeseries: Codable, Sendable {
        let since: String
        let until: String
        let requests: Totals.Requests
        let bandwidth: Totals.Bandwidth
        let threats: Totals.Threats
        let pageviews: Totals.Pageviews
        let uniques: Totals.Uniques
    }
}
