import SwiftUI

/// Services tab: Workers, KV, R2, D1, Pages (permission-gated).
struct ServicesView: View {
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            List {
                Section("Compute") {
                    if session.permissions.workers {
                        NavigationLink {
                            WorkerScriptsView(session: session)
                        } label: {
                            Label("Workers", systemImage: "doc.plaintext")
                        }
                    } else {
                        Label("Workers", systemImage: "doc.plaintext")
                            .foregroundStyle(.cfTextTertiary)
                            .badge("No access")
                    }
                }
                Section("Storage") {
                    storageRow(title: "KV", icon: "cabinet", enabled: session.permissions.kv) {
                        KVNamespacesView()
                    }
                    storageRow(title: "R2", icon: "externaldrive", enabled: session.permissions.r2) {
                        R2BucketsView()
                    }
                    storageRow(title: "D1", icon: "tablecells", enabled: session.permissions.d1) {
                        D1DatabasesView()
                    }
                    storageRow(title: "Pages", icon: "doc.append", enabled: session.permissions.pages) {
                        PagesProjectsView()
                    }
                }
            }
            .inkList()
            .navigationTitle("Services")
            .toolbar { ToolbarItem(placement: .cancellationAction) { SheetCloseButton() } }
        }
    }

    @ViewBuilder
    private func storageRow<D: View>(title: String, icon: String, enabled: Bool, destination: () -> D) -> some View {
        if enabled {
            NavigationLink {
                destination()
            } label: {
                Label(title, systemImage: icon)
            }
        } else {
            Label(title, systemImage: icon)
                .foregroundStyle(.cfTextTertiary)
                .badge("No access")
        }
    }
}

#Preview { ServicesView() }
