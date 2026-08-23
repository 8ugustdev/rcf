import SwiftUI

/// Shell-level cache of the account's zones. Loaded once per auth session,
/// refreshed on zone switch; feeds the sidebar + (later) the command palette.
/// No fetch-on-type: consumers read this snapshot only.
@MainActor
@Observable
final class ZoneCache {
    private(set) var zones: [Zone] = []
    private(set) var loading = false
    private(set) var failure: String?

    let session: Session

    init(session: Session) {
        self.session = session
    }

    /// Fetches the first page (50 zones — covers the common case; more pages
    /// load lazily in the full zones browser).
    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let (list, _): ([Zone], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.zones(page: 1)
            )
            zones = list
            failure = nil
        } catch {
            failure = (error as? CloudflareError)?.userMessage ?? "Failed to load zones"
        }
    }

    func zone(id: String) -> Zone? {
        zones.first { $0.id == id }
    }
}
