import Foundation

/// DNS record DTOs (mirror RN `services/types.ts`).

nonisolated enum DNSRecordType: String, Codable, Sendable, CaseIterable {
    case a = "A", aaaa = "AAAA", cname = "CNAME", mx = "MX", txt = "TXT", ns = "NS", srv = "SRV"
    case caa = "CAA", cert = "CERT", dnskey = "DNSKEY", ds = "DS", https = "HTTPS", loc = "LOC"
    case naptr = "NAPTR", ptr = "PTR", smimea = "SMIMEA", sshfp = "SSHFP", svcb = "SVCB", tlsa = "TLSA", uri = "URI"
    /// Forward-compatible fallback for record types added by Cloudflare.
    case unknown = "UNKNOWN"

    /// Do not offer the fallback type in create/filter pickers.
    static let allCases: [DNSRecordType] = [
        .a, .aaaa, .cname, .mx, .txt, .ns, .srv, .caa, .cert, .dnskey, .ds,
        .https, .loc, .naptr, .ptr, .smimea, .sshfp, .svcb, .tlsa, .uri,
    ]

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DNSRecordType(rawValue: raw.uppercased()) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct DNSRecord: Codable, Sendable, Identifiable {
    let id: String
    let zoneId: String
    let zoneName: String
    var name: String
    var type: DNSRecordType
    var content: String
    let proxiable: Bool
    var proxied: Bool?
    var ttl: Int
    let locked: Bool
    var comment: String?
    var tags: [String]?
    let createdOn: String?
    let modifiedOn: String?
    var priority: Int?
    var data: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, name, type, content, proxiable, proxied, ttl, locked, comment, tags, priority, data
        case zoneId = "zone_id"
        case zoneName = "zone_name"
        case createdOn = "created_on"
        case modifiedOn = "modified_on"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        zoneId = try values.decodeIfPresent(String.self, forKey: .zoneId) ?? ""
        zoneName = try values.decodeIfPresent(String.self, forKey: .zoneName) ?? ""
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(DNSRecordType.self, forKey: .type)
        content = try values.decode(String.self, forKey: .content)
        proxiable = try values.decodeIfPresent(Bool.self, forKey: .proxiable) ?? false
        proxied = try values.decodeIfPresent(Bool.self, forKey: .proxied)
        ttl = try values.decodeIfPresent(Int.self, forKey: .ttl) ?? 1
        locked = try values.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        comment = try values.decodeIfPresent(String.self, forKey: .comment)
        tags = try values.decodeIfPresent([String].self, forKey: .tags)
        createdOn = try values.decodeIfPresent(String.self, forKey: .createdOn)
        modifiedOn = try values.decodeIfPresent(String.self, forKey: .modifiedOn)
        priority = try values.decodeIfPresent(Int.self, forKey: .priority)
        data = try values.decodeIfPresent(JSONValue.self, forKey: .data)
    }
}

/// Body for create/update record calls.
nonisolated struct DNSRecordInput: Encodable, Sendable {
    var type: DNSRecordType
    var name: String
    var content: String
    var ttl: Int?
    var proxied: Bool?
    var priority: Int?
    var comment: String?
}
