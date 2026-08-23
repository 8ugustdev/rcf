import SwiftUI

/// Preview + sequential apply of template records with per-record results.
struct TemplateApplyView: View {
    struct ApplyResult: Identifiable {
        let id = UUID()
        let input: DNSRecordInput
        var success: Bool
        var message: String?
    }

    let zone: Zone
    let session: Session
    let records: [DNSRecordInput]
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var results: [ApplyResult] = []
    @State private var running = false
    @State private var done = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    resultRow(record)
                }
                if running {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                if done {
                    Section {
                        let ok = results.filter(\.success).count
                        Label("\(ok)/\(records.count) records created", systemImage: ok == records.count ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ok == records.count ? .cfSuccess : .cfWarning)
                    }
                }
            }
            .inkList()
            .navigationTitle("Apply Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.cfTextSecondary)
                    }
                    .accessibilityLabel(done ? "Done" : "Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply() }
                        .disabled(running || done)
                }
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ record: DNSRecordInput) -> some View {
        let result = results.first { $0.input.name == record.name && $0.input.content == record.content }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(record.type.rawValue)
                        .font(.caption.bold().monospaced())
                        .foregroundStyle(.cfInfo)
                    Text(record.name)
                        .font(.body.weight(.medium))
                }
                Text(record.content)
                    .font(.caption)
                    .foregroundStyle(.cfTextSecondary)
                if let message = result?.message, !result!.success {
                    Text(message).font(.caption2).foregroundStyle(.cfDanger)
                }
            }
            Spacer()
            if let result {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? .cfSuccess : .cfDanger)
            } else if running && isNextPending(record) {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func isNextPending(_ record: DNSRecordInput) -> Bool {
        record.name == records[results.count].name && record.content == records[results.count].content
    }

    private func apply() {
        running = true
        Task {
            var applied: [ApplyResult] = []
            for record in records {
                do {
                    let _: CloudflareResponse<DNSRecord> = try await session.client.send(
                        CloudflareEndpoint.createDNSRecord(zoneId: zone.id, input: record)
                    )
                    applied.append(ApplyResult(input: record, success: true))
                } catch {
                    applied.append(ApplyResult(input: record, success: false, message: (error as? CloudflareError)?.userMessage ?? "Failed"))
                }
                results = applied
            }
            running = false
            done = true
            Haptics.success()
        }
    }
}

extension DNSRecordInput: Identifiable {
    public var id: String { "\(type.rawValue)-\(name)-\(content)" }
}

extension TemplateApplyView {
    /// Shared result rendering used by the template detail screen.
    struct ResultsSection: View {
        let results: [ApplyResult]

        var body: some View {
            Section("Last Apply") {
                ForEach(results) { result in
                    HStack {
                        Text("\(result.input.type.rawValue) \(result.input.name)")
                            .font(.caption)
                        Spacer()
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.success ? .cfSuccess : .cfDanger)
                    }
                }
            }
        }
    }
}
