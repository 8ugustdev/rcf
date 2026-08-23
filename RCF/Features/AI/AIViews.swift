import SwiftUI

struct AISettingsView: View {
    @State private var backend = AIProviderStore().loadBackend()
    @State private var provider = AIProviderStore().load()
    @State private var status: String?
    private let store = AIProviderStore()

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Provider", selection: $backend) {
                    ForEach(AIBackend.allCases) { backend in
                        Text(backend.title).tag(backend)
                    }
                }
            }

            if backend == .appleIntelligence {
                Section("Apple Intelligence") {
                    LabeledContent("Processing", value: "On device")
                    if let message = AppleIntelligenceClient().availabilityMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.cfWarning)
                    } else {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.cfSuccess)
                    }
                }
                Section("Privacy") {
                    Text("Zone configuration and activity are processed on this device and are not sent to an external AI provider.")
                }
            } else {
                Section("OpenAI-compatible Provider") {
                    TextField("Base URL", text: $provider.baseURL)
                        .textInputAutocapitalization(.never).keyboardType(.URL)
                    TextField("Model", text: $provider.model).textInputAutocapitalization(.never)
                    SecureField("API key", text: $provider.apiKey).textInputAutocapitalization(.never)
                }
                Section {
                    Button("Save & Test Connection") { testConnection() }
                        .disabled(provider.baseURL.isEmpty || provider.model.isEmpty || provider.apiKey.isEmpty)
                    if let status {
                        Text(status).font(.footnote)
                            .foregroundStyle(status == "Connection successful" ? .cfSuccess : .cfTextSecondary)
                    }
                }
                Section("Privacy") {
                    Text("Zone configuration and activity selected for AI analysis will be sent to your configured provider. Your API key remains in this device’s Keychain.")
                }
            }
        }
        .inkList()
        .navigationTitle("AI Provider")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: backend) { _, value in store.saveBackend(value) }
        .onDisappear {
            store.saveBackend(backend)
            store.save(provider)
        }
    }

    private func testConnection() {
        store.save(provider)
        status = "Testing…"
        Task {
            do {
                _ = try await AIService(backend: .openAICompatible, provider: provider)
                    .chat(messages: [.init(role: "user", content: "Reply with OK only.")])
                status = "Connection successful"
            } catch { status = error.localizedDescription }
        }
    }
}

struct ZoneAuditView: View {
    let zone: Zone
    let session: Session
    @State private var result: AuditResult?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if let message = AIService().availabilityMessage {
                ContentUnavailableView("AI Unavailable", systemImage: "sparkles", description: Text(message))
            } else if loading { LoadingView(title: "Auditing zone…") }
            else if let result { auditContent(result) }
            else if let errorText { ErrorRetryView(message: errorText) { Task { await run() } } }
            else { ContentUnavailableView("Ready to audit", systemImage: "checkmark.shield", description: Text("Review DNS, SSL, firewall, and zone settings.")) }
        }
        .navigationTitle("AI Zone Audit")
        .toolbar { Button(result == nil ? "Run" : "Re-run") { Task { await run() } }.disabled(loading) }
    }

    private func auditContent(_ result: AuditResult) -> some View {
        List {
            Section("Score") { LabeledContent("Security & performance") { Text("\(result.score)/100").font(.title2.bold()).foregroundStyle(result.score >= 80 ? .cfSuccess : .cfWarning) }; Text(result.summary) }
            Section("Findings") {
                ForEach(result.findings) { finding in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Badge(text: finding.severity.rawValue.uppercased(), style: finding.severity == .critical || finding.severity == .high ? .danger : .warning); Text(finding.title).font(.headline) }
                        Text(finding.detail).font(.subheadline)
                        Label(finding.action, systemImage: "arrow.right.circle").font(.caption).foregroundStyle(.cfAccent)
                    }.padding(.vertical, 3)
                }
            }
        }
        .inkList()
    }

    private func run() async {
        loading = true; errorText = nil; defer { loading = false }
        do {
            async let settingsResponse: CloudflareResponse<[ZoneSettingValue]> = session.client.send(CloudflareEndpoint.zoneSettings(zoneId: zone.id))
            async let recordsResult: ([DNSRecord], ResultInfo?) = session.client.sendList(CloudflareEndpoint.dnsRecords(zoneId: zone.id, page: 1))
            async let sslResponse: CloudflareResponse<[CertificatePack]> = session.client.send(CloudflareEndpoint.sslCertificatePack(zoneId: zone.id))
            async let firewallResult: ([FirewallRule], ResultInfo?) = session.client.sendList(CloudflareEndpoint.firewallRules(zoneId: zone.id))
            let settings = try await settingsResponse.result?.reduce(into: [String: JSONValue]()) { $0[$1.id] = $1.value } ?? [:]
            let records = try await recordsResult.0
            let ssl = try await sslResponse.result ?? []
            let firewall = try await firewallResult.0
            result = try await AIService().json(AuditResult.self, messages: AIPrompts.audit(zoneName: zone.name, settings: settings, records: records, sslPacks: ssl, firewallCount: firewall.count))
        } catch { errorText = error.localizedDescription }
    }
}

struct TrafficInsightsView: View {
    let zone: Zone
    let analytics: GraphQLAnalytics
    @State private var insight: TrafficInsight?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let message = AIService().availabilityMessage { Text(message).foregroundStyle(.cfTextSecondary) }
            else if loading { HStack { Spacer(); ProgressView(); Spacer() } }
            else if let insight {
                Section("Summary") { Text(insight.summary) }
                Section("Observations") { ForEach(insight.observations, id: \.self) { Label($0, systemImage: "eye") } }
                Section("Recommendations") { ForEach(insight.recommendations, id: \.self) { Label($0, systemImage: "lightbulb") } }
            } else if let errorText { Text(errorText).foregroundStyle(.cfDanger) }
            else { Button("Generate Insights") { Task { await run() } } }
        }.navigationTitle("AI Traffic Insights")
        .inkList()
    }

    private func run() async {
        loading = true; defer { loading = false }
        do { insight = try await AIService().json(TrafficInsight.self, messages: AIPrompts.traffic(zoneName: zone.name, analytics: analytics)) }
        catch { errorText = error.localizedDescription }
    }
}

struct ExplainLogSheet: View {
    let description: String
    @Environment(\.dismiss) private var dismiss
    @State private var explanation = ""
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ScrollView { Group { if loading { ProgressView() } else { Text(explanation).frame(maxWidth: .infinity, alignment: .leading) } }.padding() }
                .navigationTitle("AI Explanation").toolbar { SheetCloseButton() }
                .task {
                    do { explanation = try await AIService().chat(messages: AIPrompts.explain(logDescription: description)) }
                    catch { explanation = error.localizedDescription }
                    loading = false
                }
        }
    }
}

struct DNSSuggestView: View {
    let zone: Zone
    let session: Session
    @State private var purpose = ""
    @State private var suggestions: [SuggestedDNSRecord] = []
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Goal") { TextField("e.g. Point www to my hosting service", text: $purpose, axis: .vertical); Button("Suggest Records") { Task { await suggest() } }.disabled(purpose.isEmpty || loading) }
            if loading { ProgressView() }
            if let message { Text(message).font(.footnote).foregroundStyle(.cfTextSecondary) }
            Section("Suggestions") {
                ForEach(suggestions) { record in
                    VStack(alignment: .leading) { Text("\(record.type)  \(record.name)").font(.headline); Text(record.content).font(.caption.monospaced()); if let reason = record.reason { Text(reason).font(.caption).foregroundStyle(.cfTextSecondary) }; Button("Apply") { Task { await apply(record) } } }
                }
            }
        }.navigationTitle("AI DNS Suggest")
        .inkList()
    }

    private func suggest() async {
        loading = true; message = nil; defer { loading = false }
        do { suggestions = try await AIService().json([SuggestedDNSRecord].self, messages: AIPrompts.dns(domain: zone.name, purpose: purpose)) }
        catch { message = error.localizedDescription }
    }

    private func apply(_ record: SuggestedDNSRecord) async {
        guard let type = DNSRecordType(rawValue: record.type) else { message = "Unsupported DNS type"; return }
        do {
            let input = DNSRecordInput(type: type, name: record.name, content: record.content, ttl: record.ttl ?? 1, proxied: record.proxied ?? false, priority: nil, comment: "Suggested by AI")
            let _: CloudflareResponse<DNSRecord> = try await session.client.send(CloudflareEndpoint.createDNSRecord(zoneId: zone.id, input: input))
            message = "Applied \(record.type) \(record.name)"
        } catch { message = error.localizedDescription }
    }
}
