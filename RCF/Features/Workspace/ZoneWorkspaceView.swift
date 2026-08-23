import SwiftUI

/// Zone workspace: the 2.0 home surface. Header stats strip (24h rollup) over
/// the zone detail grid (reused), with global shell actions in the toolbar.
struct ZoneWorkspaceView: View {
    let zone: Zone
    let session: Session
    var onSwitchZone: () -> Void

    @State private var stats: ZoneAnalyticsDashboard.Totals?
    @State private var statsLoaded = false

    var body: some View {
        ZoneDetailView(zone: zone, session: session)
            .safeAreaInset(edge: .top, spacing: 0) {
                if statsLoaded {
                    statsStrip
                } else {
                    EmptyView()
                }
            }
            .task(id: zone.id) {
                stats = await ZoneStatsService.zoneTotals(
                    client: session.client,
                    analyticsAllowed: session.permissions.analytics,
                    zoneId: zone.id
                )
                statsLoaded = true
            }
    }

    /// 24h traffic strip pinned under the nav bar.
    private var statsStrip: some View {
        HStack(spacing: 0) {
            if let stats {
                stat(Formatters.compact(stats.requests.all), "requests")
                Divider().frame(height: 24)
                stat(stats.requests.all > 0
                     ? "\(Int((Double(stats.requests.cached) / Double(stats.requests.all)) * 100))%"
                     : "—", "cached")
                Divider().frame(height: 24)
                stat(Formatters.compact(stats.threats.all), "threats")
                stat(Formatters.compact(stats.uniques.all), "visitors")
            } else {
                Label("24h analytics unavailable for this token", systemImage: "chart.xyaxis.line")
                    .font(.caption)
                    .foregroundStyle(.cfTextSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.cfFooter)
        .onTapGesture(perform: onSwitchZone)
        .accessibilityLabel("24 hour stats. Tap to switch zone.")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.cfText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.cfTextTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
