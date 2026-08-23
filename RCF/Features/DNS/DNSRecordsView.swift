import SwiftUI

/// DNS records list w/ type filter, search, batch ops, editor, import/export.
struct DNSRecordsView: View {
    @State private var model: DNSRecordsViewModel
    /// Single source of truth for the editor sheet; nil = closed.
    /// Prevents stale-state races where a row tap opened the create form.
    private enum EditorTarget: Identifiable {
        case new
        case edit(DNSRecord)

        var id: String {
            switch self {
            case .new: "new"
            case let .edit(record): "edit-\(record.id)"
            }
        }

        var record: DNSRecord? {
            switch self {
            case .new: nil
            case let .edit(record): record
            }
        }
    }

    @State private var editorTarget: EditorTarget?
    @State private var showingTemplates = false
    @State private var showingImportExport = false
    @State private var confirmDelete: DNSRecord?

    init(zone: Zone, session: Session) {
        _model = State(initialValue: DNSRecordsViewModel(zone: zone, session: session))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                LoadingView(title: "Loading records…")
            case .empty:
                EmptyState(icon: "point.3.connected.trianglepath.dotted", title: "No records", message: model.searchText.isEmpty ? "Add a record or apply a template." : "No records match.")
            case let .error(message):
                ErrorRetryView(message: message) {
                    Task { await model.loadFirstPage() }
                }
            case .loaded:
                recordList
            }
        }
        .navigationTitle("DNS — \(model.zone.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editorTarget = .new } label: { Label("Add Record", systemImage: "plus") }
                    Button { showingTemplates = true } label: { Label("Templates", systemImage: "square.stack.3d.up") }
                    Button { showingImportExport = true } label: { Label("Import / Export", systemImage: "arrow.up.arrow.down") }
                    Button { model.selection.removeAll() } label: { Label("Clear Selection", systemImage: "xmark.circle") }
                        .disabled(model.selection.isEmpty)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            DNSEditorView(zone: model.zone, model: model, record: target.record)
        }
        .sheet(isPresented: $showingTemplates) {
            TemplateListView(zone: model.zone, session: model.session)
        }
        .sheet(isPresented: $showingImportExport) {
            ImportExportView(model: model)
        }
        .alert("Delete record?", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let record = confirmDelete { Task { await model.delete(record) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Delete \(confirmDelete?.type.rawValue ?? "") record “\(confirmDelete?.name ?? "")”?")
        }
        .safeAreaInset(edge: .bottom) {
            if !model.selection.isEmpty {
                DNSBatchBar(model: model)
            }
        }
        .task { await model.loadFirstPage() }
    }

    private var recordList: some View {
        List {
            ForEach(model.records) { record in
                HStack(spacing: 8) {
                    Button {
                        if model.selection.contains(record.id) {
                            model.selection.remove(record.id)
                        } else {
                            model.selection.insert(record.id)
                        }
                    } label: {
                        Image(systemName: model.selection.contains(record.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.selection.contains(record.id) ? .cfAccent : .cfTextTertiary)
                            .accessibilityLabel(model.selection.contains(record.id) ? "Deselect record" : "Select record")
                    }
                    .buttonStyle(.borderless)

                    DNSRecordRow(record: record, busy: model.busyRecordIds.contains(record.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editorTarget = .edit(record)
                        }
                }
                .task { await model.loadMoreIfNeeded(current: record) }
                .swipeActions {
                    Button(role: .destructive) {
                        confirmDelete = record
                    } label: { Label("Delete", systemImage: "trash") }
                    Button {
                        editorTarget = .edit(record)
                    } label: { Label("Edit", systemImage: "pencil") }
                    if model.recordIsProxyEligible(record) {
                        Button {
                            Task { await model.setProxied(record, proxied: !(record.proxied ?? false)) }
                        } label: {
                            Label(record.proxied == true ? "DNS only" : "Proxied", systemImage: record.proxied == true ? "cloud.slash" : "cloud.fill")
                        }
                        .tint(.cfAccent)
                    }
                }
            }
        }
        .inkList()
        .searchable(text: Binding(get: { model.searchText }, set: { model.searchText = $0 }), prompt: "Search name")
        .refreshable { await model.loadFirstPage() }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Picker("Type", selection: Binding(
                    get: { model.typeFilter },
                    set: { model.typeFilter = $0 }
                )) {
                    Text("All").tag("")
                    ForEach(DNSRecordType.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

struct DNSRecordRow: View {
    let record: DNSRecord
    let busy: Bool

    var typeColor: Color {
        switch record.type {
        case .a, .aaaa: .cfInfo
        case .cname, .ns: .cfWarning
        case .mx: .cfSuccess
        case .txt: .cfTextSecondary
        case .srv, .caa, .ptr: .cfDanger
        default: .cfTextSecondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if busy { ProgressView().controlSize(.small) }
            Text(record.type.rawValue)
                .font(.caption.bold().monospaced())
                .foregroundStyle(typeColor)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(record.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if record.proxied == true {
                        Image(systemName: "cloud.fill")
                            .font(.caption2)
                            .foregroundStyle(.cfAccent)
                    }
                }
                Text(record.content)
                    .font(.caption)
                    .foregroundStyle(.cfTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.ttl == 1 ? "Auto" : "\(record.ttl)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.cfTextTertiary)
                if let priority = record.priority {
                    Text("prio \(priority)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.cfTextTertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Batch operations bar for multi-selected records.
struct DNSBatchBar: View {
    let model: DNSRecordsViewModel

    var body: some View {
        HStack {
            Text("\(model.selection.count) selected")
                .font(.footnote.weight(.medium))
            Spacer()
            Button {
                Task { await model.batchSetProxied(true) }
            } label: { Image(systemName: "cloud.fill") }
            Button {
                Task { await model.batchSetProxied(false) }
            } label: { Image(systemName: "cloud.slash") }
            Button(role: .destructive) {
                Task { await model.batchDelete() }
            } label: { Image(systemName: "trash") }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
