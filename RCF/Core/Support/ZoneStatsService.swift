import Foundation
import os

/// Diagnostic logger for analytics rollup failures (visible in device console).
nonisolated let ZoneStatsLog = Logger(subsystem: "dev.8ugust.rcf", category: "zoneStats")

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

    /// Aggregates hourly groups across zones. Query shape mirrors
    /// `MonitorEngine.hourlyQuery` (schema-valid: zone filters take zone tags
    /// only; date filters and sum/uniq live on `httpRequests1hGroups`).
    /// Returns nil only when the query fails — a zone with no traffic in the
    /// window decodes to all-zero totals, not "unavailable".
    private static func totals(client: CloudflareClient, zoneIds: [String]) async -> ZoneAnalyticsDashboard.Totals? {
        let zoneTags = zoneIds.map { "\"\($0)\"" }.joined(separator: ",")
        let since = GraphQLDate.string(from: Date.now.addingTimeInterval(-86400))
        let until = GraphQLDate.string(from: .now)
        let query = """
        { viewer { zones(filter: { zoneTag_in: [\(zoneTags)] }) {
          httpRequests1hGroups(limit: 24, filter: { datetime_geq: "\(since)", datetime_leq: "\(until)" }, orderBy: [datetime_ASC]) {
            dimensions { datetime }
            sum { requests cachedRequests bytes cachedBytes threats pageViews }
            uniq { uniques }
          }
        } } }
        """
        struct Rollup: Decodable, @unchecked Sendable {
            let viewer: Viewer
            struct Viewer: Decodable, @unchecked Sendable { let zones: [ZoneNode] }
            struct ZoneNode: Decodable, @unchecked Sendable { let httpRequests1hGroups: [Group]? }
            struct Group: Decodable, @unchecked Sendable {
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
        guard let rollup = try? await client.graphql(query: query) as Rollup else {
            ZoneStatsLog.error("rollup failed zones=\(zoneIds.count)")
            return nil
        }
        let groups = rollup.viewer.zones.flatMap { $0.httpRequests1hGroups ?? [] }
        let requests = groups.reduce(0) { $0 + ($1.sum?.requests ?? 0) }
        let cached = groups.reduce(0) { $0 + ($1.sum?.cachedRequests ?? 0) }
        let bytes = groups.reduce(0) { $0 + ($1.sum?.bytes ?? 0) }
        let cachedBytes = groups.reduce(0) { $0 + ($1.sum?.cachedBytes ?? 0) }
        let threats = groups.reduce(0) { $0 + ($1.sum?.threats ?? 0) }
        let pageviews = groups.reduce(0) { $0 + ($1.sum?.pageViews ?? 0) }
        let uniques = groups.reduce(0) { $0 + ($1.uniq?.uniques ?? 0) }
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
