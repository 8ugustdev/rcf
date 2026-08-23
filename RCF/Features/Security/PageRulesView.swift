import Foundation
import SwiftUI

/// Page Rules list + delete (RN parity: no create/toggle editor).
@MainActor
@Observable
final class PageRulesViewModel {
    enum State { case loading, loaded, empty, error(String) }

    let zone: Zone
    let session: Session
    private(set) var state: State = .loading
    private(set) var rules: [PageRule] = []

    init(zone: Zone, session: Session) {
        self.zone = zone
        self.session = session
    }

    func load() async {
        state = .loading
        do {
            let (list, _): ([PageRule], ResultInfo?) = try await session.client.sendList(CloudflareEndpoint.pageRules(zoneId: zone.id))
            rules = list
            state = list.isEmpty ? .empty : .loaded
        } catch {
            state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load page rules")
        }
    }

    func delete(_ rule: PageRule) async {
        do {
            let _: CloudflareResponse<NullResult> = try await session.client.send(CloudflareEndpoint.deletePageRule(zoneId: zone.id, ruleId: rule.id))
            rules.removeAll { $0.id == rule.id }
            if rules.isEmpty { state = .empty }
            Haptics.success()
        } catch {
            Haptics.error()
        }
    }
}

struct PageRulesView: View {
    @State private var model: PageRulesViewModel
    @State private var confirmDelete: PageRule?

    init(zone: Zone, session: Session) {
        _model = State(initialValue: PageRulesViewModel(zone: zone, session: session))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading: LoadingView(title: "Loading page rules…")
            case .empty: EmptyState(icon: "number.square", title: "No page rules", message: "Page Rules apply settings to URL patterns. Create them in the Cloudflare dashboard.")
            case let .error(message): ErrorRetryView(message: message) { Task { await model.load() } }
            case .loaded:
                List {
                    ForEach(model.rules) { rule in
                        PageRuleRow(rule: rule)
                            .swipeActions {
                                Button(role: .destructive) {
                                    confirmDelete = rule
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
                .inkList()
                .refreshable { await model.load() }
            }
        }
        .navigationTitle("Page Rules")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete page rule?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let rule = confirmDelete { Task { await model.delete(rule) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Rule for \(confirmDelete?.targets.first?.constraint.value ?? "URL") will be removed.")
        }
        .task { await model.load() }
    }
}

struct PageRuleRow: View {
    let rule: PageRule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rule.targets.first?.constraint.value ?? "—")
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Badge(text: rule.status.capitalized, style: rule.status == "active" ? .success : .neutral)
                Text("#\(rule.priority)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cfTextTertiary)
            }
            HStack(spacing: 6) {
                ForEach(rule.actions, id: \.id) { action in
                    Badge(text: action.id, style: .info)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
