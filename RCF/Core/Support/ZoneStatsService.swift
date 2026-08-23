import Foundation

/// GraphQL analytics rollups shared by workspace stats strip + insights hub.
/// Extracted from the old dashboard view model. All calls degrade to nil —
/// stats are supplementary, never blocking.
nonisolated enum ZoneStatsService {
    /// 24h rollup across up to 10 zones. Returns nil when analytics is
    /// disallowed, empty input, or the query fails.
    static func rollup(
        client: CloudflareClient,
        analyticsAllowed: Bool,
        zoneIds: [String]
    ) async -> ZoneAnalyticsDashboard.Totals? {
        guard analyticsAllowed, !zoneIds.isEmpty else { return nil }
        let ids = Array(zoneIds.prefix(10))
        return await totals(client: client, zoneIds: ids)
    }

    /// 24h rollup for a single zone.
    static func zoneTotals(
        client: CloudflareClient,
        analyticsAllowed: Bool,
        zoneId: String
    ) async -> ZoneAnalyticsDashboard.Totals? {
        guard analyticsAllowed else { return nil }
        return await totals(client: client, zoneIds: [zoneId])
    }

    private static func totals(client: CloudflareClient, zoneIds: [String]) async -> ZoneAnalyticsDashboard.Totals? {
        let zoneTags = zoneIds.map { "\"\($0)\"" }.joined(separator: ",")
        let since = GraphQLDate.string(from: Date.now.addingTimeInterval(-86400))
        let until = GraphQLDate.string(from: .now)
        let query = """
        { viewer { zones(filter: {zoneTag_in: [\(zoneTags)], date_geq: "\(since)", date_lt: "\(until)"}) {
          sum { requests cachedRequests bytes cachedBytes threats pageViews }
          uniq { uniques }
        } } }
        """
        struct Rollup: Decodable, @unchecked Sendable {
            let viewer: Viewer
            struct Viewer: Decodable, @unchecked Sendable { let zones: [ZoneStats] }
            struct ZoneStats: Decodable, @unchecked Sendable {
                let sum: Sum?
                let uniq: Uniq?
            }
            struct Sum: Decodable, @unchecked Sendable {
                let requests: Int?
                let cachedRequests: Int?
                let bytes: Int?
                let cachedBytes: Int?
                let threats: Int?
                let pageViews: Int?
            }
            struct Uniq: Decodable, @unchecked Sendable { let uniques: Int? }
        }
        guard let rollup = try? await client.graphql(query: query) as Rollup else { return nil }
        let sums = rollup.viewer.zones.compactMap(\.sum)
        guard !sums.isEmpty else { return nil }
        let requests = sums.reduce(0) { $0 + ($1.requests ?? 0) }
        let cached = sums.reduce(0) { $0 + ($1.cachedRequests ?? 0) }
        let bytes = sums.reduce(0) { $0 + ($1.bytes ?? 0) }
        let cachedBytes = sums.reduce(0) { $0 + ($1.cachedBytes ?? 0) }
        let threats = sums.reduce(0) { $0 + ($1.threats ?? 0) }
        let pageviews = sums.reduce(0) { $0 + ($1.pageViews ?? 0) }
        let uniques = rollup.viewer.zones.reduce(0) { $0 + ($1.uniq?.uniques ?? 0) }
        return ZoneAnalyticsDashboard.Totals(
            requests: .init(all: requests, cached: cached, uncached: requests - cached),
            bandwidth: .init(all: bytes, cached: cachedBytes, uncached: bytes - cachedBytes),
            threats: .init(all: threats),
            pageviews: .init(all: pageviews),
            uniques: .init(all: uniques)
        )
    }
}

/// UTC ISO8601 helper for GraphQL date filters (avoids Foundation encoder name clash).
nonisolated enum GraphQLDate {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
