import SwiftUI

/// Mission-control surface: account band, zone health rows, alerts, AI.
struct InsightsView: View {
    let session: Session
    let zoneCache: ZoneCache
    var onOpenZone: (Zone) -> Void

    @State private var model: InsightsViewModel?

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingView(title: "Loading insights…")
            }
        }
        .navigationTitle("Insights")
        .toolbar { ToolbarItem(placement: .cancellationAction) { SheetCloseButton() } }
        .navigationBarTitleDisplayMode(.inline)
        .inkNavChrome()
        .task {
            guard model == nil else { return }
            let m = InsightsViewModel(session: session, zones: zoneCache.zones)
            await m.load()
            model = m
        }
    }

    @ViewBuilder
    private func content(model: InsightsViewModel) -> some View {
        switch model.state {
        case .loading:
            LoadingView(title: "Loading insights…")
        case let .error(message):
            ErrorRetryView(message: message) {
                Task { await model.load() }
            }
        case .loaded:
            List {
                accountBand(model: model)
                if !model.alerts.isEmpty {
                    alertsSection(model: model)
                }
                zoneHealthSection(model: model)
                aiSection(model: model)
            }
            .inkList()
            .refreshable { await model.load() }
        }
    }

    // MARK: - Account band

    private func accountBand(model: InsightsViewModel) -> some View {
        Section("Last 24 hours") {
            if let totals = model.totals {
                HStack(spacing: 8) {
                    StatChip(value: Formatters.compact(totals.requests.all), label: "requests")
                    StatChip(
                        value: totals.requests.all > 0
                            ? "\(Int((Double(totals.requests.cached) / Double(totals.requests.all)) * 100))%"
                            : "—",
                        label: "cached"
                    )
                    StatChip(value: Formatters.compact(totals.threats.all), label: "threats",
                             tint: totals.threats.all > 0 ? .cfDanger : .cfText)
                }
                HStack(spacing: 8) {
                    StatChip(value: Formatters.compact(totals.bandwidth.all), label: "bytes")
                    StatChip(value: Formatters.compact(totals.pageviews.all), label: "page views")
                    StatChip(value: Formatters.compact(totals.uniques.all), label: "visitors")
                }
            } else if model.totalsUnavailable {
                Label("Analytics unavailable for this token", systemImage: "chart.xyaxis.line")
                    .font(.footnote)
                    .foregroundStyle(.cfTextSecondary)
            }
        }
    }

    // MARK: - Alerts

    private func alertsSection(model: InsightsViewModel) -> some View {
        Section("Recent Alerts") {
            ForEach(model.alerts.prefix(10)) { alert in
                HStack(spacing: 10) {
                    Image(systemName: alert.kind.icon)
                        .foregroundStyle(alert.kind.tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(.callout)
                            .foregroundStyle(.cfText)
                        Text(alert.at, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.cfTextTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Zone health (lazy per-row)

    private func zoneHealthSection(model: InsightsViewModel) -> some View {
        Section("Zone Health") {
            ForEach(model.zones) { zone in
                Button {
                    onOpenZone(zone)
                } label: {
                    ZoneHealthRow(zone: zone, totals: model.zoneTotals[zone.id])
                }
                .buttonStyle(.plain)
                .task { await model.loadZoneTotals(zone) }
            }
        }
    }

    // MARK: - AI entries

    private func aiSection(model: InsightsViewModel) -> some View {
        Section("AI") {
            if model.aiAvailable {
                NavigationLink {
                    TrafficInsightsView(zone: model.zones.first ?? .placeholder, analytics: GraphQLAnalytics())
                } label: {
                    Label("Traffic Insights", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(model.zones.isEmpty)
                NavigationLink {
                    ZoneAuditView(zone: model.zones.first ?? .placeholder, session: session)
                } label: {
                    Label("Security Audit", systemImage: "shield.checkerboard")
                }
                .disabled(model.zones.isEmpty)
            } else {
                Label(AIService().availabilityMessage ?? "AI unavailable", systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.cfTextSecondary)
            }
        }
    }
}

/// One zone's health line: name + mini stats once loaded.
struct ZoneHealthRow: View {
    let zone: Zone
    let totals: ZoneAnalyticsDashboard.Totals?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(zone.status == "active" ? Color.cfSuccess : Color.cfWarning)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.cfText)
                if let totals {
                    HStack(spacing: 10) {
                        Text("\(Formatters.compact(totals.requests.all)) req")
                        if totals.requests.all > 0 {
                            Text("\(Int((Double(totals.requests.cached) / Double(totals.requests.all)) * 100))% cached")
                        }
                        if totals.threats.all > 0 {
                            Text("\(totals.threats.all) threats")
                                .foregroundStyle(.cfDanger)
                        }
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.cfTextSecondary)
                } else {
                    Text("…")
                        .font(.caption)
                        .foregroundStyle(.cfTextTertiary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.cfTextTertiary)
        }
        .padding(.vertical, 2)
    }
}

nonisolated extension Zone {
    /// Placeholder used when a view requires a zone but the account has none.
    static var placeholder: Zone {
        Zone(
            id: "", name: "—", status: "pending", paused: false, type: "full",
            developmentMode: 0, nameServers: [], originalNameServers: nil,
            originalRegistrar: nil, modifiedOn: nil, createdOn: nil, activatedOn: nil,
            plan: Zone.ZonePlan(id: "", name: "", price: 0, currency: "", frequency: "", isSubscribed: false),
            account: Zone.ZoneAccount(id: "", name: "")
        )
    }
}

nonisolated extension MonitorAlert.Kind {
    var tint: Color {
        switch self {
        case .down, .ssl: .cfDanger
        case .spike: .cfWarning
        case .threats: .cfInfo
        }
    }
}
