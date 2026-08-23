import Foundation

/// Workers, KV, R2, D1, Pages DTOs.

nonisolated struct WorkerScript: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let etag: String?
    let handlers: [String]?
    let modifiedOn: String?
    let createdOn: String?
    let usageModel: String?
    let logpush: Bool?

    enum CodingKeys: String, CodingKey {
        case id, etag, handlers, logpush
        case modifiedOn = "modified_on"
        case createdOn = "created_on"
        case usageModel = "usage_model"
    }
}

nonisolated struct KVNamespace: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let supportsURLEncoding: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title
        case supportsURLEncoding = "supports_url_encoding"
    }
}

nonisolated struct KVKey: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let expiration: Int?
    let metadata: String?

    var id: String { name }
}

/// R2 bucket list response nests buckets one level: `result.buckets[]`.
nonisolated struct R2BucketList: Codable, Sendable {
    let buckets: [R2Bucket]
}

nonisolated struct R2Bucket: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let creationDate: String?
    let location: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, location
        case creationDate = "creation_date"
    }
}

/// Alias used by permission probing (decodes plain bucket arrays).
typealias R2BucketListItem = R2Bucket

nonisolated struct R2Object: Codable, Sendable, Identifiable, Hashable {
    let key: String
    let size: Int
    let etag: String?
    let lastModified: String?
    let httpEtag: String?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, size, etag
        case lastModified = "last_modified"
        case httpEtag = "http_etag"
    }
}

nonisolated struct PagesProject: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let subdomain: String?
    let domains: [String]?
    let createdOn: String?
    let productionBranch: String?
    let latestDeployment: LatestDeployment?

    struct LatestDeployment: Codable, Sendable, Hashable {
        let id: String
        let url: String?
        let environment: String?
        let createdOn: String?

        enum CodingKeys: String, CodingKey {
            case id, url, environment
            case createdOn = "created_on"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, subdomain, domains, latestDeployment
        case createdOn = "created_on"
        case productionBranch = "production_branch"
    }
}

nonisolated struct D1Database: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let version: String?
    let createdAt: String?
    let numTables: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, version
        case createdAt = "created_at"
        case numTables = "num_tables"
    }
}

nonisolated struct D1QueryResult: Codable, Sendable {
    struct Result: Codable, Sendable {
        let results: [JSONValue]?
        let success: Bool
        let meta: JSONValue?
    }
    let result: [Result]
    let success: Bool
    let errors: [CloudflareError.APIError]?
    let messages: [CloudflareError.APIError]?
}
