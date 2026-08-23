import SwiftUI

/// Template browser: category sections → detail (apply flow).
struct TemplateListView: View {
    let zone: Zone
    let session: Session

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(DnsTemplate.Category.allCases, id: \.self) { category in
                    let templates = DnsTemplateLibrary.all.filter { $0.category == category }
                    Section {
                        ForEach(templates) { template in
                            NavigationLink {
                                TemplateDetailView(zone: zone, session: session, template: template)
                            } label: {
                                TemplateRow(template: template)
                            }
                        }
                    } header: {
                        headerLabel(category)
                    }
                }
            }
            .inkList()
            .navigationTitle("DNS Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
            }
        }
    }

    private func headerLabel(_ category: DnsTemplate.Category) -> some View {
        switch category {
        case .hosting: Text("Hosting")
        case .email: Text("Email")
        case .verification: Text("Verification")
        case .security: Text("Security")
        }
    }
}

struct TemplateRow: View {
    let template: DnsTemplate

    private var iconImage: String {
        switch template.icon {
        case "cloud": "cloud.fill"
        case "code": "chevron.left.forwardslash.chevron.right"
        case "doc": "doc.fill"
        case "envelope": "envelope.fill"
        case "checkmark.seal": "checkmark.seal.fill"
        case "shield": "shield.fill"
        case "lock": "lock.fill"
        default: "square.stack.3d.up"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconImage)
                .foregroundStyle(.cfAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.body.weight(.medium))
                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.cfTextSecondary)
                    .lineLimit(2)
            }
        }
    }
}

/// Template detail: placeholder form → preview → sequential apply with per-record results.
struct TemplateDetailView: View {
    let zone: Zone
    let session: Session
    let template: DnsTemplate

    @State private var values: [String: String] = [:]
    @State private var useSubdomain = false
    @State private var targetName = "www"
    @State private var showingPreview = false
    @State private var applying = false
    @State private var results: [TemplateApplyView.ApplyResult]?
    @State private var previewRecords: [DNSRecordInput] = []

    var body: some View {
        Form {
            if template.targetModeChoosable {
                Section("Target") {
                    Picker("Record set", selection: $useSubdomain) {
                        Text("Apex (\(zone.name))").tag(false)
                        Text("Subdomain").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if useSubdomain {
                        TextField("Subdomain (www, app, api…)", text: $targetName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }

            if !template.placeholders.isEmpty {
                Section("Values") {
                    ForEach(template.placeholders, id: \.key) { placeholder in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(placeholder.label)
                                if placeholder.required {
                                    Text("*").foregroundStyle(.cfDanger)
                                }
                            }
                            .font(.caption)
                            TextField(placeholder.placeholder, text: binding(placeholder.key))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                }
            }

            Section {
                Button {
                    previewRecords = expanded()
                    showingPreview = true
                } label: {
                    Label("Preview Records", systemImage: "eye")
                }
                if let docs = template.docs {
                    Link(destination: URL(string: docs)!) {
                        Label("Provider docs", systemImage: "book")
                    }
                }
            }

            if let results {
                TemplateApplyView.ResultsSection(results: results)
            }
        }
        .inkList()
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPreview) {
            TemplateApplyView(zone: zone, session: session, records: previewRecords) {
                showingPreview = false
            }
            .onDisappear {
                // refresh list results after apply sheet closes
                if let applied = appliedResults { results = applied }
            }
        }
    }

    @State private var appliedResults: [TemplateApplyView.ApplyResult]?

    private func binding(_ key: String) -> Binding<String> {
        Binding(
            get: { values[key] ?? "" },
            set: { values[key] = $0 }
        )
    }

    private func expanded() -> [DNSRecordInput] {
        TemplateExpander.apply(template, options: .init(
            values: values,
            useSubdomain: useSubdomain,
            targetName: targetName
        ))
    }
}
