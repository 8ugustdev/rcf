import SwiftUI

/// Monitoring config + alert history screens.
struct MonitorConfigView: View {
    @Environment(Session.self) private var session
    @State private var config = MonitorConfig.default
    @State private var zones: [Zone] = []
    @State private var loading = true
    @State private var scheduler = MonitorScheduler()
    @State private var checkNowResult: String?

    private let store = MonitorStore()

    var body: some View {
        Form {
            Section {
                Toggle("Enable Monitoring", isOn: Binding(
                    get: { config.enabled },
                    set: { on in
                        Task {
                            if on {
                                // Request notification permission only when enabling.
                                _ = await MonitorScheduler.requestNotificationPermission()
                            }
                            config.enabled = on
                            persist()
                            if on {
                                scheduler.scheduleBackgroundRefresh()
                            }
                        }
                    }
                ))
            } header: {
                Text("Status")
            } footer: {
                Text("Background checks are best-effort on iOS; opening the app triggers a check if due.")
            }

            Section {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ForEach(zones) { zone in
                        Toggle(zone.name, isOn: Binding(
                            get: { config.zoneIds.contains(zone.id) },
                            set: { on in
                                if on {
                                    config.zoneIds.append(zone.id)
                                } else {
                                    config.zoneIds.removeAll { $0 == zone.id }
                                }
                                persist()
                            }
                        ))
                    }
                }
            } header: {
                Text("Zones")
            } footer: {
                Text("\(config.zoneIds.count) selected")
            }

            Section("Thresholds") {
                Stepper("Error rate ≥ \(config.errorRatePct)%", value: Binding(
                    get: { config.errorRatePct },
                    set: { config.errorRatePct = $0; persist() }
                ), in: 1...100)
                Stepper("Traffic spike ≥ \(config.spikeMultiplier)× avg", value: Binding(
                    get: { config.spikeMultiplier },
                    set: { config.spikeMultiplier = $0; persist() }
                ), in: 2...20)
                Stepper("SSL expiry ≤ \(config.sslDaysBefore) days", value: Binding(
                    get: { config.sslDaysBefore },
                    set: { config.sslDaysBefore = $0; persist() }
                ), in: 1...90)
            }

            Section {
                Button {
                    Task {
                        let alerts = await scheduler.runCycle(clientProvider: CurrentSessionClient.shared)
                        checkNowResult = alerts.isEmpty ? "No alerts" : "\(alerts.count) alert(s)"
                    }
                } label: {
                    Label("Check Now", systemImage: "bolt.horizontal")
                }
                .disabled(!config.enabled || scheduler.isRunning)
                if let checkNowResult {
                    Text(checkNowResult).font(.footnote).foregroundStyle(.cfAccent)
                }
                NavigationLink {
                    MonitorAlertsView()
                } label: {
                    Label("Alert History", systemImage: "bell.badge")
                }
            } header: {
                Text("Actions")
            }
        }
        .inkList()
        .navigationTitle("Monitoring")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            config = store.loadConfig()
            if let accountId = session.accountId,
               let (list, _): ([Zone], ResultInfo?) = try? await session.client.sendList(CloudflareEndpoint.zones(page: 1)) {
                zones = list
            }
            loading = false
        }
    }

    private func persist() {
        store.saveConfig(config)
    }
}

/// Alert history list + clear.
struct MonitorAlertsView: View {
    @State private var alerts: [MonitorAlert] = []
    private let store = MonitorStore()

    var body: some View {
        Group {
            if alerts.isEmpty {
                EmptyState(icon: "bell.slash", title: "No alerts", message: "Triggered alerts appear here.")
            } else {
                List {
                    ForEach(alerts) { alert in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: alert.kind.icon)
                                    .foregroundStyle(alert.kind == .down || alert.kind == .threats ? .cfDanger : .cfWarning)
                                Text(alert.title)
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)
                            }
                            Text(alert.body)
                                .font(.caption)
                                .foregroundStyle(.cfTextSecondary)
                            Text(Formatters.relative(alert.at))
                                .font(.caption2)
                                .foregroundStyle(.cfTextTertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .inkList()
                .refreshable { alerts = store.loadHistory() }
            }
        }
        .navigationTitle("Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") {
                    store.clearHistory()
                    alerts = []
                }
                .disabled(alerts.isEmpty)
            }
        }
        .task { alerts = store.loadHistory() }
    }
}
