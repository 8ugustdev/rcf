import Foundation

/// Builds a Session: tolerant identity resolution chain (RN auth.tsx parity):
/// user (optional) → accounts (optional) → zones sample (optional) → permissions probe.
@MainActor
enum SessionFactory {
    static func makeSession(client: CloudflareClient, profile: Profile) async -> Session {
        var user: CloudflareUser?
        var accounts: [Account] = []
        var zonesAccessible = false
        var sampleZone: Zone?

        // 1. User (token may lack User:Read — fine).
        if let response: CloudflareResponse<CloudflareUser> = try? await client.send(CloudflareRequest(path: "/user")) {
            user = response.result
        }

        // 2. Accounts (may lack Account Settings:Read).
        if let (list, _): ([Account], ResultInfo?) = try? await client.sendList(
            CloudflareRequest(path: "/accounts", query: [URLQueryItem(name: "per_page", value: "50")])
        ) {
            accounts = list
        }

        // 3. Zones: accessibility signal + account derivation fallback.
        if let (zones, _): ([Zone], ResultInfo?) = try? await client.sendList(
            CloudflareRequest(path: "/zones", query: [URLQueryItem(name: "per_page", value: "50")])
        ) {
            zonesAccessible = true
            sampleZone = zones.first
            if accounts.isEmpty {
                let map = zones.reduce(into: [String: Account]()) { acc, zone in
                    acc[zone.account.id] = Account(id: zone.account.id, name: zone.account.name, settings: nil)
                }
                accounts = Array(map.values)
            }
        }

        // Pick default account (RN parity: own-account heuristic, else last).
        var accountId: String?
        if let user, !accounts.isEmpty {
            let localPart = user.email.split(separator: "@").first?.lowercased() ?? ""
            accountId = accounts.first { $0.name.lowercased().contains(localPart) }?.id
                ?? accounts.last?.id
        } else {
            accountId = accounts.first?.id
        }

        var permissions = Permissions()
        if let accountId, let sampleZone {
            permissions = await PermissionProber(client: client).probe(accountId: accountId, zoneId: sampleZone.id)
        }
        permissions.zones = zonesAccessible || permissions.zones

        return Session(
            client: client,
            profile: profile,
            user: user,
            accounts: accounts,
            accountId: accountId,
            permissions: permissions,
            sampleZoneId: sampleZone?.id
        )
    }
}
