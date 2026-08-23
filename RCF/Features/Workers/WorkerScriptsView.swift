import Foundation
import SwiftUI

/// Workers script list + routes models.
@MainActor
@Observable
final class WorkersViewModel {
    enum State { case loading, loaded, empty, error(String) }

    let session: Session
    private(set) var state: State = .loading
    private(set) var scripts: [WorkerScript] = []
    private(set) var routesByZone: [String: [WorkerRoute]] = [:]

    init(session: Session) {
        self.session = session
    }

    func load() async {
        state = .loading
        guard let accountId = session.accountId else {
            state = .error("No account selected")
            return
        }
        do {
            let (list, _): ([WorkerScript], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.workerScripts(accountId: accountId)
            )
            scripts = list
            state = list.isEmpty ? .empty : .loaded
        } catch {
            state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load Workers")
        }
    }

    func delete(_ script: WorkerScript) async {
        guard let accountId = session.accountId else { return }
        do {
            let _: CloudflareResponse<NullResult> = try await session.client.send(
                CloudflareEndpoint.deleteWorkerScript(accountId: accountId, name: script.id)
            )
            scripts.removeAll { $0.id == script.id }
            if scripts.isEmpty { state = .empty }
            Haptics.success()
        } catch {
            Haptics.error()
        }
    }

    func routes(zoneId: String) async -> [WorkerRoute] {
        if let cached = routesByZone[zoneId] { return cached }
        guard let (list, _): ([WorkerRoute], ResultInfo?) = try? await session.client.sendList(
            CloudflareEndpoint.workerRoutes(zoneId: zoneId)
        ) else { return [] }
        routesByZone[zoneId] = list
        return list
    }
}

/// Worker route (pattern + script).
nonisolated struct WorkerRoute: Codable, Sendable, Identifiable {
    let id: String
    let pattern: String
    let script: String?
}

/// Services tab: Workers list (later phases add KV/R2/D1/Pages).
struct WorkerScriptsView: View {
    @State private var model: WorkersViewModel
    @State private var confirmDelete: WorkerScript?
    @State private var routesZone: Zone?
    @State private var routes: [WorkerRoute] = []

    init(session: Session) {
        _model = State(initialValue: WorkersViewModel(session: session))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading: LoadingView(title: "Loading Workers…")
            case .empty: EmptyState(icon: "doc.plaintext", title: "No Workers", message: "Deploy a Worker script in the Cloudflare dashboard.")
            case let .error(message): ErrorRetryView(message: message) { Task { await model.load() } }
            case .loaded:
                List {
                    Section("Scripts") {
                        ForEach(model.scripts) { script in
                            NavigationLink {
                                if let accountId = model.session.accountId {
                                    TailConsoleView(accountId: accountId, script: script.id, session: model.session)
                                } else {
                                    EmptyState(icon: "person.crop.circle.badge.exclamationmark", title: "No account", message: "Switch accounts and try again.")
                                }
                            } label: {
                                WorkerScriptRow(script: script)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    confirmDelete = script
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
                .inkList()
                .refreshable { await model.load() }
            }
        }
        .navigationTitle("Workers")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Worker?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete Forever", role: .destructive) {
                if let script = confirmDelete { Task { await model.delete(script) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("“\(confirmDelete?.id ?? "")” will be removed permanently.")
        }
        .task { await model.load() }
    }
}

struct WorkerScriptRow: View {
    let script: WorkerScript

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(script.id)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let usage = script.usageModel {
                    Badge(text: usage.replacingOccurrences(of: "_", with: " "), style: .neutral)
                }
            }
            if let modified = script.modifiedOn {
                Text("Modified \(modified.prefix(10))")
                    .font(.caption)
                    .foregroundStyle(.cfTextSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Per-zone worker routes (read-only parity).
struct WorkerRoutesView: View {
    let zone: Zone
    let session: Session
    @State private var routes: [WorkerRoute] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                LoadingView(title: "Loading routes…")
            } else if routes.isEmpty {
                EmptyState(icon: "arrow.triangle.branch", title: "No routes", message: "This zone has no Worker routes.")
            } else {
                List(routes) { route in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.pattern)
                            .font(.body.weight(.medium).monospaced())
                        if let script = route.script {
                            Text("→ \(script)")
                                .font(.caption)
                                .foregroundStyle(.cfTextSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Worker Routes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let (list, _): ([WorkerRoute], ResultInfo?) = try? await session.client.sendList(
                CloudflareEndpoint.workerRoutes(zoneId: zone.id)
            ) {
                routes = list
            }
            loading = false
        }
    }
}
