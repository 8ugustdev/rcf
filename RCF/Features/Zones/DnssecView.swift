import SwiftUI

/// DNSSEC status + enable/disable with copyable DS record.
struct DnssecView: View {
    let model: ZoneDetailViewModel
    @State private var confirmDisable = false

    var body: some View {
        Form {
            if let dnssec = model.dnssec {
                Section("Status") {
                    LabeledContent("Status") {
                        Badge(text: dnssec.status.capitalized, style: dnssec.status == "active" ? .success : .neutral)
                    }
                    if let modified = dnssec.modifiedOn {
                        LabeledContent("Updated") { Text(modified) }
                    }
                }

                if let ds = dnssec.dsRecord, !ds.isEmpty {
                    Section {
                        Button {
                            UIPasteboard.general.string = ds
                        } label: {
                            Label("Copy DS Record", systemImage: "doc.on.doc")
                        }
                        Text(ds)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } header: {
                        Text("DS Record")
                    } footer: {
                        Text("Add this record at your registrar to complete activation.")
                    }
                }

                Section {
                    if dnssec.status == "active" || dnssec.status == "pending" {
                        Button(role: .destructive) {
                            confirmDisable = true
                        } label: {
                            Label("Disable DNSSEC", systemImage: "xmark.shield")
                        }
                    } else {
                        Button {
                            Task { await model.setDnssec(true) }
                        } label: {
                            Label("Enable DNSSEC", systemImage: "checkmark.shield")
                        }
                        .disabled(model.busy)
                    }
                    if let message = model.message {
                        Text(message).font(.footnote).foregroundStyle(.cfAccent)
                    }
                }
            } else {
                LoadingView(title: "Loading DNSSEC…")
            }
        }
        .inkList()
        .navigationTitle("DNSSEC")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Disable DNSSEC?", isPresented: $confirmDisable) {
            Button("Disable", role: .destructive) {
                Task { await model.setDnssec(false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes DNSSEC protection from the zone.")
        }
    }
}
