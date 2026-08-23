import SwiftUI

/// Argo Smart Routing: toggle with graceful paid-feature degradation.
struct ArgoView: View {
    let model: ZoneDetailViewModel

    var body: some View {
        Form {
            Section {
                if model.argoIsPaidFeature {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Paid feature", systemImage: "crown")
                            .foregroundStyle(.cfWarning)
                        Text("Argo Smart Routing requires a paid Cloudflare plan or a token with the Zone:Edit + Argo permission.")
                            .font(.footnote)
                            .foregroundStyle(.cfTextSecondary)
                    }
                } else {
                    Toggle("Smart Routing", isOn: Binding(
                        get: { model.argoEnabled ?? false },
                        set: { on in Task { await model.setArgo(on) } }
                    ))
                    .disabled(model.busy)
                }
                if let message = model.message {
                    Text(message).font(.footnote).foregroundStyle(.cfAccent)
                }
            } header: {
                Text("Argo")
            } footer: {
                Text("Optimizes routing between Cloudflare datacenters and your origin.")
            }
        }
        .inkList()
        .navigationTitle("Argo")
        .navigationBarTitleDisplayMode(.inline)
    }
}
