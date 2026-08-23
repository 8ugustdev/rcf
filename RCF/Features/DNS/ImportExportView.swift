import SwiftUI
import UniformTypeIdentifiers

/// BIND file import (fileImporter → multipart) + export (raw → ShareLink).
struct ImportExportView: View {
    let model: DNSRecordsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showingImporter = false
    @State private var proxiedImport = false
    @State private var importSummary: String?
    @State private var importError: String?
    @State private var exportText: String?
    @State private var exportError: String?
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Proxy imported records", isOn: $proxiedImport)
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import BIND file", systemImage: "square.and.arrow.down")
                    }
                    if let importSummary {
                        Label(importSummary, systemImage: "checkmark.circle")
                            .foregroundStyle(.cfSuccess)
                            .font(.footnote)
                    }
                    if let importError {
                        Label(importError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.cfDanger)
                            .font(.footnote)
                    }
                } header: {
                    Text("Import")
                } footer: {
                    Text("BIND zone file from your registrar or a previous export. Records are added — existing ones are untouched.")
                }

                Section {
                    Button {
                        Task { await runExport() }
                    } label: {
                        Label("Export zone file", systemImage: "square.and.arrow.up")
                    }
                    if let exportError {
                        Label(exportError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.cfDanger)
                            .font(.footnote)
                    }
                    if let exportText {
                        ScrollView(.horizontal) {
                            Text(exportText)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        if let exportURL {
                            ShareLink(item: exportURL) {
                                Label("Share \(exportURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Raw BIND text from Cloudflare — share or save via the share sheet.")
                }
            }
            .inkList()
            .navigationTitle("Import / Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.text, .plainText, .data], onCompletion: importFile)
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Cannot access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let data = try Data(contentsOf: url)
                Task {
                    do {
                        let summary = try await model.importBIND(fileData: data, filename: url.lastPathComponent, proxied: proxiedImport)
                        importSummary = "Added \(summary.recsAdded) of \(summary.totalRecordsParsed) parsed records."
                        importError = nil
                    } catch {
                        importError = (error as? CloudflareError)?.userMessage ?? "Import failed"
                    }
                }
            } catch {
                importError = "Cannot read file: \(error.localizedDescription)"
            }
        case let .failure(error):
            importError = error.localizedDescription
        }
    }

    private func runExport() async {
        do {
            let text = try await model.exportBIND()
            exportText = text
            exportError = nil
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(model.zone.name).txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            exportError = (error as? CloudflareError)?.userMessage ?? "Export failed"
        }
    }
}
