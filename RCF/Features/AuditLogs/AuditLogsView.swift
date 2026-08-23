import Foundation
import SwiftUI

/// Audit log viewer: paged 50, newest first, infinite scroll, detail sheet.
@MainActor
@Observable
final class AuditLogsViewModel {
    enum State { case loading, loaded, empty, error(String) }

    let session: Session
    private(set) var state: State = .loading
    private(set) var entries: [AuditLogEntry] = []
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private var page = 1

    init(session: Session) {
        self.session = session
    }

    func loadFirstPage() async {
        state = entries.isEmpty ? .loading : .loaded
        page = 1
        hasMore = true
        await fetch(page: 1)
    }

    func loadMoreIfNeeded(current entry: AuditLogEntry) async {
        guard hasMore, !isLoadingMore, entry.id == entries.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        await fetch(page: page)
    }

    private func fetch(page: Int) async {
        guard let accountId = session.accountId else {
            state = .error("No account selected")
            return
        }
        do {
            let (list, info): ([AuditLogEntry], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.auditLogs(accountId: accountId, page: page)
            )
            if page == 1 {
                entries = list
            } else {
                entries.append(contentsOf: list)
            }
            hasMore = (info?.totalPages ?? 1) > page && !list.isEmpty
            state = entries.isEmpty ? .empty : .loaded
        } catch {
            if page == 1 {
                state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load audit logs")
            }
        }
    }
}

/// Audit logs screen.
struct AuditLogsView: View {
    @Environment(Session.self) private var session
    @State private var model: AuditLogsViewModel?
    @State private var selected: AuditLogEntry?

    var body: some View {
        Group {
            if let model {
                content(model: model)
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Audit Logs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil {
                model = AuditLogsViewModel(session: session)
            }
            await model?.loadFirstPage()
        }
    }

    @ViewBuilder
    private func content(model: AuditLogsViewModel) -> some View {
        switch model.state {
        case .loading:
            LoadingView(title: "Loading audit logs…")
        case .empty:
            EmptyState(icon: "doc.text.magnifyingglass", title: "No audit logs", message: "Account activity will appear here.")
        case let .error(message):
            ErrorRetryView(message: message) {
                Task { await model.loadFirstPage() }
            }
        case .loaded:
            List {
                ForEach(model.entries) { entry in
                    AuditLogRow(entry: entry)
                        .task { await model.loadMoreIfNeeded(current: entry) }
                        .onTapGesture { selected = entry }
                }
            }
            .inkList()
            .refreshable { await model.loadFirstPage() }
            .sheet(item: $selected) { entry in
                AuditLogDetailSheet(entry: entry)
            }
        }
    }
}

struct AuditLogRow: View {
    let entry: AuditLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.actionType?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Action")
                    .font(.body.weight(.medium))
                Spacer()
                Badge(text: "OK", style: .success)
            }
            Text(Masking.email(entry.actorEmail ?? "system"))
                .font(.caption)
                .foregroundStyle(.cfTextSecondary)
            HStack {
                if let resource = entry.resourceName {
                    Text(resource)
                        .font(.caption2)
                        .lineLimit(1)
                }
                Spacer()
                Text(shortDate(entry.when))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.cfTextTertiary)
                if let ip = entry.ip {
                    Text(ip)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.cfTextTertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func shortDate(_ iso: String) -> String {
        // ISO → "Aug 23, 14:05"
        let input = ISO8601DateFormatter()
        input.formatOptions = [.withInternetDateTime]
        guard let date = input.date(from: iso) else { return iso }
        return Formatters.shortDateTime.string(from: date)
    }
}

/// Detail sheet with metadata rendering.
struct AuditLogDetailSheet: View {
    let entry: AuditLogEntry
    @Environment(\.dismiss) private var dismiss
    @State private var showExplanation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Event") {
                    LabeledContent("Action") { Text(entry.actionType ?? "—") }
                    LabeledContent("When") { Text(entry.when) }
                    if let ip = entry.ip {
                        LabeledContent("IP") { Text(ip).monospaced() }
                    }
                    LabeledContent("Actor") { Text(entry.actorEmail ?? "system") }
                    LabeledContent("Actor type") { Text(entry.actorType ?? "—") }
                }
                Section("Resource") {
                    LabeledContent("Type") { Text(entry.resourceType ?? "—") }
                    LabeledContent("Name") { Text(entry.resourceName ?? "—") }
                }
                if let metadata = entry.metadata, metadata != .null {
                    Section("Metadata") {
                        Text(metadata.displayString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                if AIService().isAvailable {
                    Section("AI") {
                        Button("Explain this event") { showExplanation = true }
                    }
                }
            }
            .inkList()
            .navigationTitle("Audit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { SheetCloseButton() }
            }
            .sheet(isPresented: $showExplanation) {
                ExplainLogSheet(description: "Action: \(entry.actionType ?? "unknown"); actor: \(entry.actorType ?? "unknown"); resource: \(entry.resourceType ?? "unknown") \(entry.resourceName ?? ""); metadata: \(entry.metadata?.displayString ?? "none")")
            }
        }
    }
}
