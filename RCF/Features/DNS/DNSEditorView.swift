import SwiftUI

/// Record editor: create + edit all types with per-type validation.
struct DNSEditorView: View {
    let zone: Zone
    let model: DNSRecordsViewModel
    let record: DNSRecord?   // nil = create

    @Environment(\.dismiss) private var dismiss
    @State private var type: DNSRecordType = .a
    @State private var name = ""
    @State private var content = ""
    @State private var ttl = 1
    @State private var proxied = false
    @State private var priority = 10
    @State private var hasPriority = false
    @State private var comment = ""
    @State private var submitting = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Record") {
                    Picker("Type", selection: $type) {
                        ForEach(DNSRecordType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: type) { _, newType in
                        hasPriority = newType == .mx || newType == .srv
                    }
                    TextField("Name (@ or subdomain)", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(fieldLabel, text: $content, axis: .vertical)
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if type == .txt {
                        Label("Long TXT strings auto-split at 255 chars by Cloudflare.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.cfTextSecondary)
                    }
                }

                Section("Settings") {
                    Picker("TTL", selection: $ttl) {
                        Text("Auto").tag(1)
                        ForEach([60, 300, 600, 1800, 3600, 7200, 43200, 86400], id: \.self) { seconds in
                            Text("\(seconds >= 3600 ? "\(seconds/3600)h" : "\(seconds/60)m")").tag(seconds)
                        }
                    }
                    if hasPriority {
                        Stepper("Priority \(priority)", value: $priority, in: 0...65535)
                    }
                    if proxyEligible {
                        Toggle(isOn: $proxied) {
                            Label("Proxied", systemImage: "cloud.fill")
                        }
                    }
                    TextField("Comment (optional)", text: $comment)
                }

                if let submitError {
                    Section { Text(submitError).foregroundStyle(.cfDanger).font(.footnote) }
                }
            }
            .inkList()
            .navigationTitle(record == nil ? "Add Record" : "Edit Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { submit() }
                        .disabled(!isValid || submitting)
                }
            }
        }
        .onAppear { populate() }
    }

    private var fieldLabel: String {
        switch type {
        case .a: "IPv4 address"
        case .aaaa: "IPv6 address"
        case .mx: "Mail server"
        case .srv: "Target (e.g. srv.example.com)"
        default: "Content"
        }
    }

    private var proxyEligible: Bool {
        type == .a || type == .aaaa || type == .cname
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              !content.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch type {
        case .a:
            return isValidIPv4(content)
        case .aaaa:
            return content.contains(":") // light IPv6 sanity
        case .cname:
            return name != "@" // CNAME cannot be apex
        case .mx, .srv:
            return priority >= 0
        default:
            return true
        }
    }

    private func isValidIPv4(_ string: String) -> Bool {
        let parts = string.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts.allSatisfy { (0...255).contains($0) }
    }

    private func populate() {
        if let record {
            type = record.type
            name = record.name
            content = record.content
            ttl = record.ttl == 0 ? 1 : record.ttl
            proxied = record.proxied ?? false
            comment = record.comment ?? ""
            if let p = record.priority {
                hasPriority = true
                priority = p
            }
        }
    }

    private func submit() {
        let input = DNSRecordInput(
            type: type,
            name: name.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces),
            ttl: ttl,
            proxied: proxyEligible ? proxied : nil,
            priority: hasPriority ? priority : nil,
            comment: comment.isEmpty ? nil : comment
        )
        submitting = true
        Task {
            do {
                if let record {
                    try await model.update(recordId: record.id, input: input)
                } else {
                    try await model.create(input)
                }
                dismiss()
            } catch {
                submitError = (error as? CloudflareError)?.userMessage ?? "Save failed"
            }
            submitting = false
        }
    }
}
