import SwiftUI
import UniformTypeIdentifiers

/// R2 buckets + object browser (cursor pagination, prefix filter, upload/download).
@MainActor
@Observable
final class R2ViewModel {
    enum State { case loading, loaded, empty, error(String) }

    let session: Session
    private(set) var state: State = .loading
    private(set) var buckets: [R2Bucket] = []
    private(set) var objects: [R2Object] = []
    private(set) var activeBucket: String?
    private(set) var loadingObjects = false
    private(set) var uploadProgress: Double?
    private(set) var busy = false
    var prefix = ""

    init(session: Session) {
        self.session = session
    }

    func loadBuckets() async {
        guard let accountId = session.accountId else { return }
        state = .loading
        do {
            // R2 nests result: {buckets: [...]}.
            let response: CloudflareResponse<R2BucketList> = try await session.client.send(
                CloudflareEndpoint.r2Buckets(accountId: accountId)
            )
            buckets = response.result?.buckets ?? []
            state = buckets.isEmpty ? .empty : .loaded
        } catch {
            state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load buckets")
        }
    }

    func createBucket(name: String) async {
        guard let accountId = session.accountId else { return }
        await mutate {
            let _: CloudflareResponse<R2Bucket> = try await self.session.client.send(
                try CloudflareEndpoint.createR2Bucket(accountId: accountId, name: name)
            )
        }
        await loadBuckets()
    }

    func deleteBucket(_ bucket: R2Bucket) async {
        guard let accountId = session.accountId else { return }
        await mutate {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(
                CloudflareEndpoint.deleteR2Bucket(accountId: accountId, name: bucket.name)
            )
        }
        await loadBuckets()
    }

    func loadObjects(bucket: String) async {
        guard let accountId = session.accountId else { return }
        activeBucket = bucket
        loadingObjects = true
        defer { loadingObjects = false }
        do {
            let currentPrefix = self.prefix.isEmpty ? nil : self.prefix
            objects = try await Pagination.paginateCursor([R2Object].self, client: session.client) { cursor in
                CloudflareEndpoint.r2Objects(accountId: accountId, bucket: bucket, cursor: cursor, prefix: currentPrefix)
            }
        } catch {
            objects = []
        }
    }

    func deleteObject(_ object: R2Object) async {
        guard let accountId = session.accountId, let bucket = activeBucket else { return }
        await mutate {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(
                CloudflareEndpoint.deleteR2Object(accountId: accountId, bucket: bucket, key: object.key)
            )
        }
        objects.removeAll { $0.key == object.key }
    }

    func upload(key: String, data: Data, contentType: String) async throws {
        guard let accountId = session.accountId, let bucket = activeBucket else { throw CloudflareError.notAuthenticated }
        uploadProgress = 0
        defer { uploadProgress = nil }
        // URLSession upload (progress approximation via didSendData delegate is
        // not exposed by CloudflareClient; use single-shot and report indeterminate → done).
        let _: CloudflareResponse<NullResult> = try await session.client.send(
            CloudflareEndpoint.r2Upload(accountId: accountId, bucket: bucket, key: key, data: data, contentType: contentType)
        )
        uploadProgress = 1
        Haptics.success()
        if let bucket = activeBucket {
            await loadObjects(bucket: bucket)
        }
    }

    func download(object: R2Object) async throws -> URL {
        guard let accountId = session.accountId, let bucket = activeBucket else { throw CloudflareError.notAuthenticated }
        let (data, _) = try await session.client.sendRaw(
            CloudflareEndpoint.r2Download(accountId: accountId, bucket: bucket, key: object.key)
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(object.key.split(separator: "/").last.map(String.init) ?? "object")
        try data.write(to: url, options: .atomic)
        return url
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

/// R2 browser: buckets list → object browser.
struct R2BucketsView: View {
    @Environment(Session.self) private var session
    @State private var model: R2ViewModel?
    @State private var showingCreate = false
    @State private var newName = ""
    @State private var confirmDelete: R2Bucket?

    var body: some View {
        Group {
            if let model { content(model: model) } else { LoadingView() }
        }
        .navigationTitle("R2")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .alert("New Bucket", isPresented: $showingCreate) {
            TextField("Bucket name", text: $newName)
            Button("Create") {
                Task {
                    await model?.createBucket(name: newName)
                    newName = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete bucket?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let bucket = confirmDelete { Task { await model?.deleteBucket(bucket) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Bucket “\(confirmDelete?.name ?? "")” must be empty to delete.")
        }
        .task {
            if model == nil { model = R2ViewModel(session: session) }
            await model?.loadBuckets()
        }
    }

    @ViewBuilder
    private func content(model: R2ViewModel) -> some View {
        switch model.state {
        case .loading: LoadingView(title: "Loading buckets…")
        case .empty: EmptyState(icon: "externaldrive", title: "No buckets", message: "Create an R2 bucket for object storage.")
        case let .error(message): ErrorRetryView(message: message) { Task { await model.loadBuckets() } }
        case .loaded:
            List(model.buckets) { bucket in
                NavigationLink {
                    R2ObjectBrowserView(model: model, bucket: bucket.name)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bucket.name)
                        if let created = bucket.creationDate {
                            Text("Created \(created.prefix(10))")
                                .font(.caption)
                                .foregroundStyle(.cfTextSecondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { confirmDelete = bucket } label: { Label("Delete", systemImage: "trash") }
                }
            }
            .refreshable { await model.loadBuckets() }
        }
    }
}

struct R2ObjectBrowserView: View {
    @State private var model: R2ViewModel
    let bucket: String
    @State private var showingUploader = false
    @State private var shareURL: URL?
    @State private var confirmDelete: R2Object?

    init(model: R2ViewModel, bucket: String) {
        self.model = model
        self.bucket = bucket
    }

    var body: some View {
        List(model.objects) { object in
            VStack(alignment: .leading, spacing: 2) {
                Text(object.key)
                    .font(.body.monospaced())
                    .lineLimit(1)
                HStack {
                    Text(Formatters.bytes(Int64(object.size)))
                    if let modified = object.lastModified {
                        Text("• \(modified.prefix(10))")
                    }
                    Spacer()
                    Button {
                        Task {
                            shareURL = try? await model.download(object: object)
                        }
                    } label: {
                        Label("Download", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
                .foregroundStyle(.cfTextSecondary)
            }
            .swipeActions {
                Button(role: .destructive) { confirmDelete = object } label: { Label("Delete", systemImage: "trash") }
            }
        }
        .searchable(text: Binding(
            get: { model.prefix },
            set: { model.prefix = $0 }
        ), prompt: "Prefix filter (flat)")
        .navigationTitle(bucket)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingUploader = true } label: { Image(systemName: "square.and.arrow.up") }
            }
        }
        .sheet(isPresented: $showingUploader) {
            R2UploadView(model: model, bucket: bucket)
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .alert("Delete object?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let object = confirmDelete { Task { await model.deleteObject(object) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text(confirmDelete?.key ?? "")
        }
        .overlay {
            if model.loadingObjects {
                LoadingView(title: "Listing objects…")
            } else if model.objects.isEmpty {
                EmptyState(icon: "doc", title: "No objects", message: "Upload a file or adjust the prefix filter.")
            }
        }
        .refreshable { await model.loadObjects(bucket: bucket) }
        .task { await model.loadObjects(bucket: bucket) }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

/// UIKit share sheet wrapper.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// R2 upload: file picker → key name → progress.
struct R2UploadView: View {
    let model: R2ViewModel
    let bucket: String

    @Environment(\.dismiss) private var dismiss
    @State private var showingPicker = false
    @State private var key = ""
    @State private var fileData: Data?
    @State private var contentType = "application/octet-stream"
    @State private var uploading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Object") {
                    TextField("Object key (path/name.ext)", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        showingPicker = true
                    } label: {
                        Label(fileData == nil ? "Choose File" : "File selected (\(Formatters.bytes(Int64(fileData?.count ?? 0))))", systemImage: "paperclip")
                    }
                }
                if let progress = model.uploadProgress {
                    Section("Uploading") {
                        ProgressView(value: progress)
                    }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.cfDanger).font(.footnote) }
                }
            }
            .inkList()
            .navigationTitle("Upload")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") { upload() }
                        .disabled(key.isEmpty || fileData == nil || uploading)
                }
            }
            .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.data], onCompletion: pick)
        }
    }

    private func pick(_ result: Result<URL, Error>) {
        guard case let .success(url) = result, url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        if let data = try? Data(contentsOf: url) {
            fileData = data
            if key.isEmpty {
                key = url.lastPathComponent
            }
            contentType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? contentType
        }
    }

    private func upload() {
        uploading = true
        Task {
            do {
                try await model.upload(key: key, data: fileData ?? Data(), contentType: contentType)
                dismiss()
            } catch {
                errorText = (error as? CloudflareError)?.userMessage ?? "Upload failed"
            }
            uploading = false
        }
    }
}
