import SwiftUI

/// Cache management: purge everything (typed confirm), purge by URLs, dev mode.
struct CacheView: View {
    let zoneId: String
    let zoneName: String
    let model: ZoneDetailViewModel

    @State private var urlText = ""
    @State private var confirmPurgeAll = false
    @State private var purgeConfirmText = ""

    var body: some View {
        Form {
            Section {
                Button(role: .destructive) {
                    purgeConfirmText = ""
                    confirmPurgeAll = true
                } label: {
                    Label("Purge Everything", systemImage: "arrow.triangle.2.circlepath")
                }
            } header: {
                Text("Full Purge")
            } footer: {
                Text("Removes all cached files for \(zoneName). Type the zone name to confirm.")
            }

            Section {
                TextEditor(text: $urlText)
                    .font(.system(.caption, design: .monospaced))
                    .inkEditor()
                    .frame(minHeight: 100)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Purge URLs") {
                    let urls = urlText
                        .split(separator: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    guard !urls.isEmpty else { return }
                    Task { await model.purgeURLs(urls) }
                }
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Purge by URL")
            } footer: {
                Text("One full URL per line (up to 30).")
                if let message = model.message {
                    Text(message).foregroundStyle(.cfAccent)
                }
            }

            Section {
                Toggle("Development Mode", isOn: Binding(
                    get: { model.settings["development_mode"] == .bool(true) },
                    set: { on in Task { await model.setDevelopmentMode(on) } }
                ))
                .disabled(model.busy)
            } header: {
                Text("Development Mode")
            } footer: {
                Text("Bypasses Cloudflare cache for 3 hours.")
            }
        }
        .inkList()
        .navigationTitle("Cache")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Purge everything?", isPresented: $confirmPurgeAll) {
            TextField("Type \(zoneName)", text: $purgeConfirmText)
            Button("Purge", role: .destructive) {
                guard purgeConfirmText == zoneName else { return }
                Task { await model.purgeEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All cached assets for \(zoneName) will be removed worldwide.")
        }
    }
}
