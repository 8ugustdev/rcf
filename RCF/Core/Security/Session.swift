import Foundation
import SwiftUI

/// Active session: wraps the CloudflareClient, current identity, and permission surface.
/// Rebuilt on profile or account switch; injected via SwiftUI Environment.
@MainActor
@Observable
final class Session {
    let client: CloudflareClient
    let profile: Profile

    var user: CloudflareUser?
    var accounts: [Account] = []
    var accountId: String?
    var permissions = Permissions()
    /// First zone id — used as the representative zone for permission probes.
    var sampleZoneId: String?

    init(client: CloudflareClient, profile: Profile, user: CloudflareUser? = nil, accounts: [Account] = [], accountId: String? = nil, permissions: Permissions = Permissions(), sampleZoneId: String? = nil) {
        self.client = client
        self.profile = profile
        self.user = user
        self.accounts = accounts
        self.accountId = accountId
        self.permissions = permissions
        self.sampleZoneId = sampleZoneId
    }

    /// Display identity: user email → account name → profile label.
    var displayName: String {
        user?.email ?? accounts.first?.name ?? profile.label
    }

    /// Profile with the resolved human label baked in (renames token-fingerprint labels).
    func profileUpdated() -> Profile {
        var updated = profile
        if updated.label.hasPrefix("Token ••••"), let realName = user?.email ?? accounts.first?.name {
            updated.label = realName
        }
        updated.accountId = accountId
        return updated
    }
}
