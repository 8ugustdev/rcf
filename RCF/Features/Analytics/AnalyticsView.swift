import Charts
import SwiftUI

/// Zone analytics: range picker, totals cards, Swift Charts time series.
@MainActor
@Observable
final class AnalyticsViewModel {
    enum State { case loading, loaded, empty, error(String) }

    let zone: Zone
    let session: Session
    private(set) var state: State = .loading
    private(set) var analytics = GraphQLAnalytics()
    var days = 7 {
        didSet { Task { await load() } }
    }

    init(zone: Zone, session: Session) {
        self.zone = zone
        self.session = session
    }

    func load() async {
        state = .loading
        do {
            analytics = try await session.client.zoneAnalytics(zoneId: zone.id, days: days)
            state = analytics.timeseries.isEmpty ? .empty : .loaded
        } catch {
            state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load analytics")
        }
    }
}

struct AnalyticsView: View {
    @State private var model: AnalyticsViewModel

    init(zone: Zone, session: Session) {
        _model = State(initialValue: AnalyticsViewModel(zone: zone, session: session))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading: LoadingView(title: "Loading analytics…")
            case .empty: EmptyState(icon: "chart.xyaxis.line", title: "No analytics data", message: "This zone has no traffic in the selected range.")
            case let .error(message): ErrorRetryView(message: message) { Task { await model.load() } }
            case .loaded: content
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private var content: some View {
        List {
            Picker("Range", selection: Binding(
                get: { model.days },
                set: { model.days = $0 }
            )) {
                Text("1D").tag(1)
                Text("7D").tag(7)
                Text("30D").tag(30)
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 4, trailing: 8))

            totalsSection
            Section("AI") {
                NavigationLink {
                    TrafficInsightsView(zone: model.zone, analytics: model.analytics)
                } label: {
                    Label("Generate Traffic Insights", systemImage: "sparkles")
                }
            }
            chartsSection
        }
        .inkList()
    }

    private var totalsSection: some View {
        Section("Totals") {
            let a = model.analytics
            LabeledContent("Requests") {
                Text(Formatters.compact(a.requestsTotal)).monospacedDigit()
            }
            LabeledContent("Cached") {
                let pct = a.requestsTotal > 0 ? a.requestsCached * 100 / a.requestsTotal : 0
                Text("\(pct)%").monospacedDigit()
            }
            LabeledContent("Bandwidth") {
                Text(Formatters.bytes(Int64(a.bytesTotal)))
            }
            LabeledContent("Bandwidth cached") {
                let pct = a.bytesTotal > 0 ? a.bytesCached * 100 / a.bytesTotal : 0
                Text("\(pct)%").monospacedDigit()
            }
            LabeledContent("Threats") {
                Text(Formatters.compact(a.threatsTotal))
                    .foregroundStyle(a.threatsTotal > 0 ? .cfDanger : .cfText)
            }
            LabeledContent("Page Views") { Text(Formatters.compact(a.pageviewsTotal)).monospacedDigit() }
            LabeledContent("Unique Visitors") { Text(Formatters.compact(a.uniquesTotal)).monospacedDigit() }
        }
    }

    private var chartsSection: some View {
        Section("Time Series") {
            requestsChart
                .frame(height: 180)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            bandwidthChart
                .frame(height: 160)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            threatsChart
                .frame(height: 140)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            pageviewsChart
                .frame(height: 140)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        }
    }

    private var chartDates: [Date] {
        model.analytics.timeseries.compactMap { series in
            ISO8601DateFormatter().date(from: series.date + "T00:00:00Z")
        }
    }

    private var requestsChart: some View {
        Chart {
            ForEach(Array(model.analytics.timeseries.enumerated()), id: \.offset) { index, series in
                LineMark(x: .value("Date", chartDates[index]), y: .value("Requests", series.requests))
                    .foregroundStyle(.cfAccent)
                AreaMark(x: .value("Date", chartDates[index]), y: .value("Cached", series.cachedRequests))
                    .foregroundStyle(.cfAccent.opacity(0.2))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
        .chartLegend {
            HStack(spacing: 12) {
                Label("Requests", systemImage: "line.diagonal").foregroundStyle(.cfAccent)
                Label("Cached", systemImage: "square.half.filled").foregroundStyle(.cfAccent.opacity(0.4))
            }
            .font(.caption2)
        }
    }

    private var bandwidthChart: some View {
        Chart {
            ForEach(Array(model.analytics.timeseries.enumerated()), id: \.offset) { index, series in
                AreaMark(x: .value("Date", chartDates[index]), y: .value("Bytes", Double(series.bytes) / 1_000_000))
                    .foregroundStyle(.cfInfo.opacity(0.3))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
    }

    private var threatsChart: some View {
        Chart {
            ForEach(Array(model.analytics.timeseries.enumerated()), id: \.offset) { index, series in
                BarMark(x: .value("Date", chartDates[index]), y: .value("Threats", series.threats))
                    .foregroundStyle(.cfDanger)
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
    }

    private var pageviewsChart: some View {
        Chart {
            ForEach(Array(model.analytics.timeseries.enumerated()), id: \.offset) { index, series in
                LineMark(x: .value("Date", chartDates[index]), y: .value("Page Views", series.pageViews))
                    .foregroundStyle(.cfSuccess)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) }
    }
}
