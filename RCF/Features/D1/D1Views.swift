import SwiftUI

/// D1 databases + table browser + SQL console.
@MainActor
@Observable
final class D1ViewModel {
    enum State { case loading, loaded, empty, error(String) }

    let session: Session
    private(set) var state: State = .loading
    private(set) var databases: [D1Database] = []
    private(set) var tables: [D1TableInfo] = []
    private(set) var loadingTables = false

    init(session: Session) {
        self.session = session
    }

    func loadDatabases() async {
        guard let accountId = session.accountId else { return }
        state = .loading
        do {
            let (list, _): ([D1Database], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.d1Databases(accountId: accountId)
            )
            databases = list
            state = list.isEmpty ? .empty : .loaded
        } catch {
            state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load databases")
        }
    }

    func loadTables(dbId: String) async {
        guard let accountId = session.accountId else { return }
        loadingTables = true
        defer { loadingTables = false }
        tables = (try? await session.client.d1Tables(accountId: accountId, dbId: dbId)) ?? []
    }
}

/// D1 databases list → browser.
struct D1DatabasesView: View {
    @Environment(Session.self) private var session
    @State private var model: D1ViewModel?

    var body: some View {
        Group {
            if let model { content(model: model) } else { LoadingView() }
        }
        .navigationTitle("D1")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = D1ViewModel(session: session) }
            await model?.loadDatabases()
        }
    }

    @ViewBuilder
    private func content(model: D1ViewModel) -> some View {
        switch model.state {
        case .loading: LoadingView(title: "Loading databases…")
        case .empty: EmptyState(icon: "tablecells", title: "No databases", message: "Create a D1 database in the Cloudflare dashboard.")
        case let .error(message): ErrorRetryView(message: message) { Task { await model.loadDatabases() } }
        case .loaded:
            List(model.databases) { db in
                NavigationLink {
                    D1BrowserView(session: model.session, db: db)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(db.name)
                        HStack {
                            Text(Masking.maskAccountID(db.id))
                            if let version = db.version {
                                Text("• v\(version)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.cfTextSecondary)
                    }
                }
            }
            .refreshable { await model.loadDatabases() }
        }
    }
}

/// Database browser: tables list + rows viewer + SQL console entry.
struct D1BrowserView: View {
    let session: Session
    let db: D1Database

    @State private var tables: [D1TableInfo] = []
    @State private var loading = true

    var body: some View {
        List {
            Section("Tables") {
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if tables.isEmpty {
                    Text("No user tables")
                        .foregroundStyle(.cfTextSecondary)
                }
                ForEach(tables) { table in
                    NavigationLink {
                        D1RowsView(session: session, db: db, table: table.name)
                    } label: {
                        HStack {
                            Text(table.name).font(.body.monospaced())
                            Spacer()
                            if let count = table.rowCount {
                                Text("\(count) rows").font(.caption).foregroundStyle(.cfTextSecondary)
                            }
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    SQLConsoleView(session: session, db: db)
                } label: {
                    Label("SQL Console", systemImage: "terminal")
                }
            }
        }
        .inkList()
        .navigationTitle(db.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let accountId = session.accountId {
                tables = (try? await session.client.d1Tables(accountId: accountId, dbId: db.id)) ?? []
            }
            loading = false
        }
    }
}

/// Table rows viewer: SELECT * LIMIT/OFFSET paging.
struct D1RowsView: View {
    let session: Session
    let db: D1Database
    let table: String

    @State private var rows: [[String: String]] = []
    @State private var columns: [String] = []
    @State private var offset = 0
    @State private var loading = true
    @State private var hasMore = false

    private let pageSize = 50

    var body: some View {
        Group {
            if loading && rows.isEmpty {
                LoadingView(title: "Loading rows…")
            } else if rows.isEmpty {
                EmptyState(icon: "tablecells", title: "No rows", message: "Table \(table) is empty.")
            } else {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack(spacing: 12) {
                            ForEach(columns, id: \.self) { column in
                                Text(column)
                                    .font(.caption.bold().monospaced())
                                    .foregroundStyle(.cfTextSecondary)
                                    .frame(minWidth: 90, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(columns, id: \.self) { column in
                                    Text(row[column] ?? "NULL")
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(minWidth: 90, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 3)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .navigationTitle(table)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                HStack {
                    Button("Prev") {
                        offset = max(0, offset - pageSize)
                        Task { await load() }
                    }
                    .disabled(offset == 0 || loading)
                    Text("\(offset + 1)–\(offset + rows.count)")
                        .font(.caption.monospacedDigit())
                    Spacer()
                    Button("Next") {
                        offset += pageSize
                        Task { await load() }
                    }
                    .disabled(!hasMore || loading)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard let accountId = session.accountId,
              let result = try? await session.client.d1TableRows(accountId: accountId, dbId: db.id, table: table, limit: pageSize, offset: offset),
              let first = result.result.first else { return }
        let jsonRows = first.results ?? []
        rows = jsonRows.compactMap { row in
            guard case let .object(dict) = row else { return nil }
            var cells: [String: String] = [:]
            for (key, value) in dict {
                cells[key] = value.displayString
            }
            return cells
        }
        if columns.isEmpty {
            columns = rows.first?.keys.sorted() ?? []
        }
        hasMore = rows.count == pageSize
    }
}

/// SQL console: multi-statement input → results grid + meta.
struct SQLConsoleView: View {
    let session: Session
    let db: D1Database

    @State private var sql = "SELECT name FROM sqlite_master WHERE type='table'"
    @State private var running = false
    @State private var result: D1QueryResult?
    @State private var errorText: String?
    @State private var confirmRun = false

    /// Destructive statement detection.
    private var isDestructive: Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for keyword in ["drop ", "delete ", "truncate ", "insert ", "update ", "alter ", "create "] {
            if trimmed.hasPrefix(keyword) { return true }
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextEditor(text: $sql)
                        .font(.system(.caption, design: .monospaced))
                        .inkEditor()
                        .frame(minHeight: 110)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button {
                        if isDestructive {
                            confirmRun = true
                        } else {
                            Task { await run() }
                        }
                    } label: {
                        if running {
                            HStack { ProgressView(); Text("Running…") }
                        } else {
                            Label("Run", systemImage: "play.fill")
                        }
                    }
                    .disabled(running || sql.isEmpty)
                } header: {
                    Text("SQL")
                } footer: {
                    Text("Runs against \(db.name). Write statements ask for confirmation.")
                }
            }
            .inkList()
            Divider()
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.cfDanger)
                    .font(.footnote)
                    .padding()
                Spacer()
            } else if let result {
                ResultsGridView(result: result)
            } else {
                EmptyState(icon: "terminal", title: "No results yet", message: "Run a query to see rows.")
            }
        }
        .navigationTitle("SQL Console")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Run write statement?", isPresented: $confirmRun) {
            Button("Run Anyway", role: .destructive) { Task { await run() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This modifies your database. Continue?")
        }
    }

    private func run() async {
        running = true
        errorText = nil
        defer { running = false }
        guard let accountId = session.accountId else { return }
        do {
            result = try await session.client.queryD1(accountId: accountId, dbId: db.id, sql: sql)
        } catch {
            errorText = (error as? CloudflareError)?.userMessage ?? "Query failed"
        }
    }
}

/// Results grid from the first result set + meta line.
struct ResultsGridView: View {
    let result: D1QueryResult

    private var rows: [[String: String]] {
        guard let first = result.result.first else { return [] }
        return (first.results ?? []).compactMap { row in
            guard case let .object(dict) = row else { return nil }
            return dict.mapValues { $0.displayString }
        }
    }

    private var columns: [String] {
        rows.first?.keys.sorted() ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let meta = result.result.first?.meta, case let .object(metaDict) = meta {
                let duration = metaDict["duration"]?.displayString ?? "—"
                let read = metaDict["rows_read"]?.displayString ?? "—"
                let written = metaDict["rows_written"]?.displayString ?? "—"
                Text("\(rows.count) rows • \(duration)s • read \(read) • wrote \(written)")
                    .font(.caption2)
                    .foregroundStyle(.cfTextTertiary)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }
            if rows.isEmpty {
                EmptyState(icon: "checkmark.circle", title: "OK", message: "Statement executed (no rows returned).")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            ForEach(columns, id: \.self) { column in
                                Text(column)
                                    .font(.caption.bold().monospaced())
                                    .foregroundStyle(.cfTextSecondary)
                                    .frame(minWidth: 90, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(columns, id: \.self) { column in
                                    Text(row[column] ?? "NULL")
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(minWidth: 90, alignment: .leading)
                                }
                            }
                            .padding(.vertical, 3)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
                }
            }
            Spacer()
        }
    }
}
