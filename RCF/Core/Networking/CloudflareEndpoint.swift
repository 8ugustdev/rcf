import Foundation

/// Zone-scoped endpoints (list/get/create/delete, settings, purge, DNSSEC, Argo).
nonisolated enum CloudflareEndpoint {
    struct ValueBody<T: Encodable & Sendable>: Encodable {
        let value: T
    }

    // MARK: - Zones

    static func zones(page: Int, search: String? = nil) -> CloudflareRequest {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "50"),
            URLQueryItem(name: "order", value: "name"),
            URLQueryItem(name: "direction", value: "asc"),
        ]
        if let search, !search.isEmpty {
            query.append(URLQueryItem(name: "name", value: search))
        }
        return CloudflareRequest(path: "/zones", query: query)
    }

    static func zone(id: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(id)")
    }

    static func createZone(name: String, accountId: String) throws -> CloudflareRequest {
        struct CreateZoneBody: Encodable {
            let name: String
            let account: AccountRef
            let type: String
            struct AccountRef: Encodable { let id: String }
        }
        return try CloudflareRequest.json(
            CreateZoneBody(name: name, account: .init(id: accountId), type: "full"),
            path: "/zones",
            method: .post
        )
    }

    static func deleteZone(id: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(id)", method: .delete)
    }

    // MARK: - Settings

    static func zoneSettings(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/settings")
    }

    static func zoneSetting(zoneId: String, id: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/settings/\(id)")
    }

    static func updateZoneSetting(zoneId: String, id: String, value: JSONValue) throws -> CloudflareRequest {
        try CloudflareRequest.json(ValueBody(value: value), path: "/zones/\(zoneId)/settings/\(id)", method: .patch)
    }

    // MARK: - Cache

    static func purgeAll(zoneId: String) throws -> CloudflareRequest {
        try CloudflareRequest.json(ValueBody(value: true), path: "/zones/\(zoneId)/purge_cache", method: .post)
    }

    /// Purge-Everything marker: post body `{"purge_everything": true}`.
    static func purgeEverything(zoneId: String) throws -> CloudflareRequest {
        struct Body: Encodable { let purgeEverything: Bool
            enum CodingKeys: String, CodingKey { case purgeEverything = "purge_everything" } }
        return try CloudflareRequest.json(Body(purgeEverything: true), path: "/zones/\(zoneId)/purge_cache", method: .post)
    }

    static func purgeURLs(zoneId: String, urls: [String]) throws -> CloudflareRequest {
        struct Body: Encodable { let files: [String] }
        return try CloudflareRequest.json(Body(files: urls), path: "/zones/\(zoneId)/purge_cache", method: .post)
    }

    // MARK: - DNSSEC / Argo / Security level

    static func dnssec(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/dnssec")
    }

    static func updateDnssec(zoneId: String, status: String) throws -> CloudflareRequest {
        struct StatusBody: Encodable { let status: String }
        return try CloudflareRequest.json(StatusBody(status: status), path: "/zones/\(zoneId)/dnssec", method: .patch)
    }

    static func argoSmartRouting(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/argo/smart_routing")
    }

    static func updateArgoSmartRouting(zoneId: String, value: Bool) throws -> CloudflareRequest {
        try CloudflareRequest.json(ValueBody(value: value), path: "/zones/\(zoneId)/argo/smart_routing", method: .patch)
    }
}

/// DNSSEC status payload.
nonisolated struct DNSSECStatus: Codable, Sendable {
    let status: String
    let dsRecord: String?
    let digestType: String?
    let dnsseckeys: JSONValue?
    let nameServers: [String]?
    let modifiedOn: String?

    enum CodingKeys: String, CodingKey {
        case status
        case dsRecord = "ds"
        case digestType = "digest_type"
        case dnsseckeys
        case nameServers = "name_servers"
        case modifiedOn = "modified_on"
    }
}

/// Zone setting shorthand values used by detail toggles.
nonisolated enum SecurityLevel: String, CaseIterable, Sendable {
    case off, essentiallyOff = "essentially_off", low, medium, high, underAttack = "under_attack"
}
