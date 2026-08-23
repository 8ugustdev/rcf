import Foundation

/// DNS record endpoints: CRUD, raw export, multipart import.
nonisolated extension CloudflareEndpoint {
    static func dnsRecords(zoneId: String, page: Int, type: String? = nil, name: String? = nil) -> CloudflareRequest {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "per_page", value: "100"),
        ]
        if let type, !type.isEmpty {
            query.append(URLQueryItem(name: "type", value: type))
        }
        if let name, !name.isEmpty {
            query.append(URLQueryItem(name: "name", value: name))
        }
        return CloudflareRequest(path: "/zones/\(zoneId)/dns_records", query: query)
    }

    static func createDNSRecord(zoneId: String, input: DNSRecordInput) throws -> CloudflareRequest {
        try CloudflareRequest.json(input, path: "/zones/\(zoneId)/dns_records", method: .post)
    }

    static func updateDNSRecord(zoneId: String, recordId: String, input: DNSRecordInput) throws -> CloudflareRequest {
        try CloudflareRequest.json(input, path: "/zones/\(zoneId)/dns_records/\(recordId)", method: .put)
    }

    static func deleteDNSRecord(zoneId: String, recordId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/dns_records/\(recordId)", method: .delete)
    }

    /// Raw BIND text export (no envelope).
    static func exportDNSZone(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/dns_records/export")
    }

    /// Multipart BIND import.
    static func importDNSZone(zoneId: String, fileData: Data, filename: String, proxied: Bool) -> CloudflareRequest {
        var body = MultipartBody()
        body.field(name: "proxied", value: proxied ? "true" : "false")
        body.file(name: "file", filename: filename, contentType: "text/plain", data: fileData)
        return CloudflareRequest(path: "/zones/\(zoneId)/dns_records/import", method: .post, body: .multipart(body))
    }
}

/// Import result summary.
nonisolated struct DNSImportResult: Decodable, Sendable {
    let recsAdded: Int
    let totalRecordsParsed: Int
    let totalRecordsProcessed: Int?

    enum CodingKeys: String, CodingKey {
        case recsAdded = "recs_added"
        case totalRecordsParsed = "total_records_parsed"
        case totalRecordsProcessed = "total_records_processed"
    }
}
