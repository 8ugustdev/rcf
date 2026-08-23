import Foundation

/// KV, R2, D1, Pages endpoints (developer platform).
nonisolated extension CloudflareEndpoint {
    // MARK: - KV

    static func kvNamespaces(accountId: String, page: Int = 1) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/storage/kv/namespaces", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "50"),
        ])
    }

    static func createKVNamespace(accountId: String, title: String) throws -> CloudflareRequest {
        struct Body: Encodable { let title: String }
        return try CloudflareRequest.json(Body(title: title), path: "/accounts/\(accountId)/storage/kv/namespaces", method: .post)
    }

    static func deleteKVNamespace(accountId: String, nsId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/storage/kv/namespaces/\(nsId)", method: .delete)
    }

    static func kvKeys(accountId: String, nsId: String, page: Int = 1) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/storage/kv/namespaces/\(nsId)/keys", query: [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    /// Raw value read (no envelope).
    static func kvValueRead(accountId: String, nsId: String, key: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/storage/kv/namespaces/\(nsId)/values/\(encodePath(key))")
    }

    /// Multipart value write.
    static func kvValueWrite(accountId: String, nsId: String, key: String, value: String) -> CloudflareRequest {
        var body = MultipartBody()
        body.field(name: "value", value: value)
        return CloudflareRequest(path: "/accounts/\(accountId)/storage/kv/namespaces/\(nsId)/values/\(encodePath(key))", method: .put, body: .multipart(body))
    }

    static func deleteKVKey(accountId: String, nsId: String, key: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/storage/kv/namespaces/\(nsId)/values/\(encodePath(key))", method: .delete)
    }

    // MARK: - R2

    static func r2Buckets(accountId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/r2/buckets")
    }

    static func createR2Bucket(accountId: String, name: String) throws -> CloudflareRequest {
        struct Body: Encodable { let name: String }
        return try CloudflareRequest.json(Body(name: name), path: "/accounts/\(accountId)/r2/buckets", method: .post)
    }

    static func deleteR2Bucket(accountId: String, name: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/r2/buckets/\(name)", method: .delete)
    }

    static func r2Objects(accountId: String, bucket: String, cursor: String? = nil, prefix: String? = nil) -> CloudflareRequest {
        var query = [URLQueryItem(name: "per_page", value: "100")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let prefix, !prefix.isEmpty { query.append(URLQueryItem(name: "prefix", value: prefix)) }
        return CloudflareRequest(path: "/accounts/\(accountId)/r2/buckets/\(bucket)/objects", query: query)
    }

    static func deleteR2Object(accountId: String, bucket: String, key: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/r2/buckets/\(bucket)/objects/\(encodePath(key))", method: .delete)
    }

    /// Raw upload (bytes + content type).
    static func r2Upload(accountId: String, bucket: String, key: String, data: Data, contentType: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/r2/buckets/\(bucket)/objects/\(encodePath(key))", method: .put, body: .raw(data, contentType: contentType))
    }

    /// Raw download.
    static func r2Download(accountId: String, bucket: String, key: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/r2/buckets/\(bucket)/objects/\(encodePath(key))")
    }

    // MARK: - D1

    static func d1Databases(accountId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/d1/database")
    }

    static func d1Query(accountId: String, dbId: String, sql: String) throws -> CloudflareRequest {
        struct Body: Encodable { let sql: String }
        return try CloudflareRequest.json(Body(sql: sql), path: "/accounts/\(accountId)/d1/database/\(dbId)/query", method: .post)
    }

    // MARK: - Pages

    static func pagesProjects(accountId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/pages/projects")
    }

    static func pagesProject(accountId: String, name: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/pages/projects/\(name)")
    }

    static func pagesDeployments(accountId: String, projectName: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/pages/projects/\(projectName)/deployments")
    }

    static func deletePagesProject(accountId: String, name: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/pages/projects/\(name)", method: .delete)
    }

    // MARK: - Helpers

    /// Percent-encodes a path segment (keys may contain slashes/specials).
    static func encodePath(_ segment: String) -> String {
        let encoded = segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? segment
        return encoded.replacingOccurrences(of: "/", with: "%2F")
    }
}

/// D1 query result row.
nonisolated struct D1QueryRow: Decodable, Sendable {
    let results: [JSONValue]?
    let success: Bool
    let meta: JSONValue?
}

/// D1 table info.
nonisolated struct D1TableInfo: Sendable, Identifiable {
    let name: String
    let rowCount: Int?
    var id: String { name }
}

/// Pages deployment (list item).
nonisolated struct PagesDeployment: Codable, Sendable, Identifiable {
    let id: String
    let environment: String?
    let createdOn: String?
    let latestStage: LatestStage?

    struct LatestStage: Codable, Sendable {
        let name: String?
        let status: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, environment
        case createdOn = "created_on"
        case latestStage = "latest_stage"
    }
}

nonisolated extension CloudflareClient {
    /// D1 query — returns the first result set (RN `queryD1` parity).
    func queryD1(accountId: String, dbId: String, sql: String) async throws -> D1QueryResult {
        let response: CloudflareResponse<[D1QueryResult.Result]> = try await send(
            try CloudflareEndpoint.d1Query(accountId: accountId, dbId: dbId, sql: sql)
        )
        // D1 returns either an array of result sets or a single result set object.
        if let array = response.result, let first = array.first {
            return D1QueryResult(result: [first], success: true, errors: response.errors, messages: response.messages)
        }
        return D1QueryResult(result: [], success: false, errors: response.errors, messages: response.messages)
    }

    /// User tables with row counts (RN `getD1Tables` verbatim SQL).
    func d1Tables(accountId: String, dbId: String) async throws -> [D1TableInfo] {
        let tablesResult = try await queryD1(
            accountId: accountId, dbId: dbId,
            sql: "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY name"
        )
        let names = (tablesResult.result.first?.results ?? []).compactMap { row -> String? in
            guard case let .object(dict) = row else { return nil }
            guard case .string(let name) = dict["name"] ?? .null else { return nil }
            return name
        }
        var tables: [D1TableInfo] = []
        for name in names {
            var count: Int?
            if let c = try? await queryD1(accountId: accountId, dbId: dbId, sql: "SELECT COUNT(*) AS n FROM \"\(Self.quoteIdentifier(name))\""),
               let first = c.result.first?.results?.first,
               case let .object(dict) = first, case .number(let n) = dict["n"] ?? .null {
                count = Int(n)
            }
            tables.append(D1TableInfo(name: name, rowCount: count))
        }
        return tables
    }

    /// Table rows with LIMIT/OFFSET paging (RN `getD1TableRows` verbatim).
    func d1TableRows(accountId: String, dbId: String, table: String, limit: Int = 50, offset: Int = 0) async throws -> D1QueryResult {
        try await queryD1(accountId: accountId, dbId: dbId, sql: "SELECT * FROM \"\(Self.quoteIdentifier(table))\" LIMIT \(limit) OFFSET \(offset)")
    }

    /// SQLite identifier quoting: `"` → `""`.
    nonisolated static func quoteIdentifier(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "\"", with: "\"\"")
    }
}
