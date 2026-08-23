import SwiftUI

/// KV namespaces → keys → value editor.
@MainActor
@Observable
final class KVViewModel {
    enum State { case loading, loaded, empty, error(String) }

    let session: Session
    private(set) var state: State = .loading
    private(set) var namespaces: [KVNamespace] = []
    private(set) var keys: [KVKey] = []
    private(set) var activeNamespace: KVNamespace?
    private(set) var loadingKeys = false
    private(set) var busy = false
    var keyFilter = ""

    private var page = 1
    private(set) var hasMoreKeys = true

    init(session: Session) {
        self.session = session
    }

    var filteredKeys: [KVKey] {
        keyFilter.isEmpty ? keys : keys.filter { $0.name.localizedCaseInsensitiveContains(keyFilter) }
    }

    func loadNamespaces() async {
        guard let accountId = session.accountId else { return }
        state = .loading
        do {
            let all = try await Pagination.paginate([KVNamespace].self, client: session.client) { page in
                CloudflareEndpoint.kvNamespaces(accountId: accountId, page: page)
            }
            namespaces = all.items
            state = all.items.isEmpty ? .empty : .loaded
        } catch {
            state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load namespaces")
        }
    }

    func createNamespace(title: String) async {
        guard let accountId = session.accountId else { return }
        await mutate {
            let _: CloudflareResponse<KVNamespace> = try await self.session.client.send(
                try CloudflareEndpoint.createKVNamespace(accountId: accountId, title: title)
            )
        }
        await loadNamespaces()
    }

    func deleteNamespace(_ ns: KVNamespace) async {
        guard let accountId = session.accountId else { return }
        await mutate {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(
                CloudflareEndpoint.deleteKVNamespace(accountId: accountId, nsId: ns.id)
            )
        }
        await loadNamespaces()
    }

    func loadKeys(ns: KVNamespace, firstPage: Bool = true) async {
        guard let accountId = session.accountId else { return }
        activeNamespace = ns
        loadingKeys = true
        defer { loadingKeys = false }
        if firstPage {
            page = 1
            hasMoreKeys = true
            keys = []
        }
        do {
            let (list, info): ([KVKey], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.kvKeys(accountId: accountId, nsId: ns.id, page: page)
            )
            keys = firstPage ? list : keys + list
            hasMoreKeys = (info?.totalPages ?? 1) > page && !list.isEmpty
        } catch {
            // non-fatal for pagination
        }
    }

    func loadMoreKeys() async {
        guard hasMoreKeys, !loadingKeys, let ns = activeNamespace else { return }
        page += 1
        await loadKeys(ns: ns, firstPage: false)
    }

    func readValue(key: String) async throws -> String {
        guard let accountId = session.accountId, let ns = activeNamespace else { throw CloudflareError.notAuthenticated }
        let (data, _) = try await session.client.sendRaw(
            CloudflareEndpoint.kvValueRead(accountId: accountId, nsId: ns.id, key: key)
        )
        return String(decoding: data, as: UTF8.self)
    }

    func writeValue(key: String, value: String) async throws {
        guard let accountId = session.accountId, let ns = activeNamespace else { throw CloudflareError.notAuthenticated }
        let _: CloudflareResponse<NullResult> = try await session.client.send(
            CloudflareEndpoint.kvValueWrite(accountId: accountId, nsId: ns.id, key: key, value: value) as CloudflareRequest
        )
    }

    func deleteKey(_ key: KVKey) async {
        guard let accountId = session.accountId, let ns = activeNamespace else { return }
        await mutate {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(
                CloudflareEndpoint.deleteKVKey(accountId: accountId, nsId: ns.id, key: key.name)
            )
        }
        keys.removeAll { $0.name == key.name }
    }

    private func mutate(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await operation()
            Haptics.success()
        } catch {
            Haptics.error()
        }
    }
}

/// KV browser screen: namespaces list, then keys, then value editor.
struct KVNamespacesView: View {
    @Environment(Session.self) private var session
    @State private var model: KVViewModel?
    @State private var showingCreate = false
    @State private var newTitle = ""
    @State private var confirmDelete: KVNamespace?

    var body: some View {
        Group {
            if let model { content(model: model) } else { LoadingView() }
        }
        .navigationTitle("KV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New Namespace", isPresented: $showingCreate) {
            TextField("Title", text: $newTitle)
            Button("Create") {
                Task {
                    await model?.createNamespace(title: newTitle)
                    newTitle = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete namespace?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let ns = confirmDelete { Task { await model?.deleteNamespace(ns) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("All keys in “\(confirmDelete?.title ?? "")” will be lost.")
        }
        .task {
            if model == nil { model = KVViewModel(session: session) }
            await model?.loadNamespaces()
        }
    }

    @ViewBuilder
    private func content(model: KVViewModel) -> some View {
        switch model.state {
        case .loading: LoadingView(title: "Loading namespaces…")
        case .empty: EmptyState(icon: "cabinet", title: "No namespaces", message: "Create a KV namespace to store key-value data.")
        case let .error(message): ErrorRetryView(message: message) { Task { await model.loadNamespaces() } }
        case .loaded:
            List(model.namespaces) { ns in
                NavigationLink {
                    KVKeysView(model: model, ns: ns)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ns.title)
                        Text(Masking.maskAccountID(ns.id))
                            .font(.caption)
                            .foregroundStyle(.cfTextSecondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { confirmDelete = ns } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .refreshable { await model.loadNamespaces() }
        }
    }
}

struct KVKeysView: View {
    @State private var model: KVViewModel
    let ns: KVNamespace
    @State private var editingKey: String?
    @State private var creatingKey = false
    @State private var confirmDelete: KVKey?

    init(model: KVViewModel, ns: KVNamespace) {
        self.model = model
        self.ns = ns
    }

    var body: some View {
        List(model.filteredKeys) { key in
            Button {
                editingKey = key.name
            } label: {
                HStack {
                    Text(key.name).font(.body.monospaced())
                    Spacer()
                    if let expiration = key.expiration {
                        Text("exp \(Formatters.relative(Date(timeIntervalSince1970: TimeInterval(expiration))))")
                            .font(.caption2)
                            .foregroundStyle(.cfWarning)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.cfTextTertiary)
                }
            }
            .task { await model.loadMoreKeys() }
            .swipeActions {
                Button(role: .destructive) { confirmDelete = key } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .searchable(text: Binding(get: { model.keyFilter }, set: { model.keyFilter = $0 }), prompt: "Filter keys (loaded pages)")
        .navigationTitle(ns.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingKey = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: Binding(
            get: { editingKey.map { KVKeySheet(key: $0) } },
            set: { editingKey = $0?.key }
        )) { sheet in
            KVValueEditor(model: model, key: sheet.key, isNew: false)
        }
        .sheet(isPresented: $creatingKey) {
            KVValueEditor(model: model, key: "", isNew: true)
        }
        .alert("Delete key?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let key = confirmDelete { Task { await model.deleteKey(key) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text(confirmDelete?.name ?? "")
        }
        .overlay {
            if model.loadingKeys && model.keys.isEmpty {
                LoadingView(title: "Loading keys…")
            } else if model.keys.isEmpty {
                EmptyState(icon: "key", title: "No keys", message: "Add a key-value pair.")
            }
        }
        .task { await model.loadKeys(ns: ns) }
    }

    private struct KVKeySheet: Identifiable {
        let key: String
        var id: String { key }
    }
}

/// KV value viewer/editor (raw + JSON pretty).
struct KVValueEditor: View {
    let model: KVViewModel
    let key: String
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var keyName = ""
    @State private var value = ""
    @State private var loading = true
    @State private var prettyJSON = false
    @State private var saving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if loading {
                    LoadingView(title: "Reading value…")
                } else {
                    Form {
                        Section("Key") {
                            if isNew {
                                TextField("key-name", text: $keyName)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                Text(keyName).font(.body.monospaced()).textSelection(.enabled)
                            }
                        }
                        Section {
                            TextEditor(text: $value)
                                .font(.system(.caption, design: .monospaced))
                                .inkEditor()
                                .frame(minHeight: 220)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            Toggle("Pretty JSON", isOn: $prettyJSON)
                            if prettyJSON {
                                Text(pretty(value))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.cfTextSecondary)
                            }
                        } header: {
                            Text("Value")
                        } footer: {
                            Text("Multipart PUT — values up to 25 MB.")
                        }
                        if let errorText {
                            Section { Text(errorText).foregroundStyle(.cfDanger).font(.footnote) }
                        }
                    }
                    .inkList()
                }
            }
            .navigationTitle(isNew ? "New Key" : "Edit Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(saving || (isNew && keyName.isEmpty))
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        keyName = key
        if !isNew {
            do {
                value = try await model.readValue(key: key)
            } catch {
                errorText = (error as? CloudflareError)?.userMessage ?? "Read failed"
            }
        }
        loading = false
    }

    private func pretty(_ json: String) -> String {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else { return "Not valid JSON" }
        return text
    }

    private func save() {
        saving = true
        Task {
            do {
                try await model.writeValue(key: isNew ? keyName : key, value: value)
                if isNew, let ns = model.activeNamespace {
                    await model.loadKeys(ns: ns)
                }
                dismiss()
            } catch {
                errorText = (error as? CloudflareError)?.userMessage ?? "Save failed"
            }
            saving = false
        }
    }
}
