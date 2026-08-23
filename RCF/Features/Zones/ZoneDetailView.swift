import SwiftUI

/// Zone detail hub: info card, quick toggles, section grid (permission-gated).
struct ZoneDetailView: View {
    let zone: Zone
    let session: Session
    @State private var model: ZoneDetailViewModel?
    @State private var confirmDelete = false
    @State private var deleteText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingView(title: "Loading zone…")
            }
        }
        .navigationTitle(zone.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = ZoneDetailViewModel(zoneId: zone.id, session: session, initialZone: zone)
            }
            await model?.load()
        }
    }

    @ViewBuilder
    private func content(model: ZoneDetailViewModel) -> some View {
        switch model.state {
        case .loading:
            LoadingView(title: "Loading zone…")
        case let .error(message):
            ErrorRetryView(message: message) {
                Task { await model.load() }
            }
        case .loaded:
            List {
                if let zone = model.zone {
                    zoneInfoSection(model: model, zone: zone)
                }
                quickTogglesSection(model: model)
                sectionsGrid(model: model)
                dangerSection(model: model)
            }
            .inkList()
            .alert("Delete zone", isPresented: $confirmDelete) {
                TextField("Type \(zone.name)", text: $deleteText)
                Button("Delete Forever", role: .destructive) {
                    guard deleteText == zone.name else { return }
                    Task {
                        try? await ZonesViewModel(session: session).deleteZone(zone)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the zone from Cloudflare. Type the zone name to confirm.")
            }
        }
    }

    private func zoneInfoSection(model: ZoneDetailViewModel, zone: Zone) -> some View {
        Section {
            LabeledContent("Status") { Badge(text: zone.status.capitalized, style: zone.status == "active" ? .success : .warning) }
            LabeledContent("Plan") { Text(zone.plan.name) }
            LabeledContent("Type") { Text(zone.type.capitalized) }
            if !zone.nameServers.isEmpty {
                LabeledContent("Nameservers") {
                    Text(zone.nameServers.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("Overview")
        }
    }

    private func quickTogglesSection(model: ZoneDetailViewModel) -> some View {
        Section {
            Toggle("Development Mode", isOn: Binding(
                get: { model.settings["development_mode"] == .bool(true) },
                set: { on in Task { await model.setDevelopmentMode(on) } }
            ))
            .disabled(model.busy)

            Toggle("Under Attack Mode", isOn: Binding(
                get: { model.settings["security_level"] == .string("under_attack") },
                set: { on in Task { await model.setUnderAttack(on) } }
            ))
            .disabled(model.busy)
        } header: {
            Text("Quick Toggles")
        } footer: {
            if let message = model.message {
                Text(message)
            }
        }
    }

    private func sectionsGrid(model: ZoneDetailViewModel) -> some View {
        Section("Zone") {
            let p = model.session.permissions
            gridRow(model: model, icon: "point.3.connected.trianglepath.dotted", title: "DNS", enabled: p.dns, destination: DNSRecordsView(zone: zone, session: model.session))
            gridRow(model: model, icon: "lock.shield", title: "SSL/TLS", enabled: p.ssl, destination: SSLView(zone: zone, session: model.session))
            gridRow(model: model, icon: "firewall", title: "Firewall", enabled: p.firewall, destination: FirewallView(zone: zone, session: model.session))
            gridRow(model: model, icon: "arrow.triangle.2.circlepath", title: "Cache", enabled: p.cache, destination: CacheView(zoneId: model.zoneId, zoneName: zone.name, model: model))
            gridRow(model: model, icon: "chart.xyaxis.line", title: "Analytics", enabled: p.analytics, destination: AnalyticsView(zone: zone, session: model.session))
            gridRow(model: model, icon: "number.square", title: "Page Rules", enabled: p.pageRules, destination: PageRulesView(zone: zone, session: model.session))
            gridRow(model: model, icon: "envelope.arrow.triangle.branch", title: "Email Routing", enabled: true, destination: EmailRoutingView(zone: zone, session: model.session))
            gridRow(model: model, icon: "checkmark.seal", title: "DNSSEC", enabled: true, destination: DnssecView(model: model))
            gridRow(model: model, icon: "bolt.horizontal", title: "Argo", enabled: true, destination: ArgoView(model: model))
            gridRow(model: model, icon: "switch.2", title: "Zone Settings", enabled: true, destination: ZoneSettingsView(model: model))
            gridRow(model: model, icon: "sparkles", title: "AI Zone Audit", enabled: true, destination: ZoneAuditView(zone: zone, session: model.session))
            gridRow(model: model, icon: "wand.and.stars", title: "AI DNS Suggest", enabled: true, destination: DNSSuggestView(zone: zone, session: model.session))
        }
    }

    @ViewBuilder
    private func gridRow<D: View>(model: ZoneDetailViewModel, icon: String, title: String, enabled: Bool, destination: D) -> some View {
        if enabled {
            NavigationLink {
                destination
            } label: {
                Label(title, systemImage: icon)
            }
        } else {
            Label(title, systemImage: icon)
                .foregroundStyle(.cfTextTertiary)
                .badge("No access")
        }
    }

    private func dangerSection(model: ZoneDetailViewModel) -> some View {
        Section {
            Button(role: .destructive) {
                deleteText = ""
                confirmDelete = true
            } label: {
                Label("Delete Zone", systemImage: "trash")
            }
        }
    }
}

// Placeholder removed — all phase-6 screens landed.
