import Foundation
import SwiftUI

/// Insights hub view model: account stats band, lazy per-zone health rows,
/// recent monitor alerts, AI availability. Everything degrades gracefully.
@MainActor
@Observable
final class InsightsViewModel {
    enum LoadState { case loading, loaded, error(String) }

    let session: Session
    let zones: [Zone]

    private(set) var state: LoadState = .loading
    private(set) var totals: ZoneAnalyticsDashboard.Totals?
    private(set) var totalsUnavailable = false
    private(set) var alerts: [MonitorAlert] = []
    /// Zone id → 24h totals, fetched lazily per visible row.
    private(set) var zoneTotals: [String: ZoneAnalyticsDashboard.Totals] = [:]

    private let store = MonitorStore()

    init(session: Session, zones: [Zone]) {
        self.session = session
        self.zones = Array(zones.prefix(10))
    }

    func load() async {
        state = .loading
        alerts = store.loadHistory()
        totals = await ZoneStatsService.rollup(
            client: session.client,
            analyticsAllowed: session.permissions.analytics,
            zoneIds: zones.map(\.id)
        )
        totalsUnavailable = totals == nil
        state = .loaded
    }

    /// Fetches one zone's 24h totals for a health row (idempotent).
    func loadZoneTotals(_ zone: Zone) async {
        guard zoneTotals[zone.id] == nil else { return }
        let t = await ZoneStatsService.zoneTotals(
            client: session.client,
            analyticsAllowed: session.permissions.analytics,
            zoneId: zone.id
        )
        zoneTotals[zone.id] = t ?? .zero
    }

    var aiAvailable: Bool {
        AIService().isAvailable
    }
}

nonisolated extension ZoneAnalyticsDashboard.Totals {
    /// Neutral empty totals for zones with no analytics access.
    static var zero: ZoneAnalyticsDashboard.Totals {
        .init(
            requests: .init(all: 0, cached: 0, uncached: 0),
            bandwidth: .init(all: 0, cached: 0, uncached: 0),
            threats: .init(all: 0),
            pageviews: .init(all: 0),
            uniques: .init(all: 0)
        )
    }
}
