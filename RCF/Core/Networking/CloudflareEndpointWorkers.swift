import Foundation

/// Workers endpoints: scripts, routes, tails.
nonisolated extension CloudflareEndpoint {
    static func workerScripts(accountId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/workers/scripts")
    }

    static func deleteWorkerScript(accountId: String, name: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/workers/scripts/\(name)", method: .delete)
    }

    static func workerRoutes(zoneId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/zones/\(zoneId)/workers/routes")
    }

    static func createWorkerTail(accountId: String, script: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/workers/scripts/\(script)/tails", method: .post)
    }

    static func deleteWorkerTail(accountId: String, script: String, tailId: String) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/workers/scripts/\(script)/tails/\(tailId)", method: .delete)
    }
}

/// Tail creation response: short-lived signed URL + id.
nonisolated struct WorkerTail: Decodable, Sendable {
    let id: String
    let url: URL
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, url
        case expiresAt = "expires_at"
    }
}
