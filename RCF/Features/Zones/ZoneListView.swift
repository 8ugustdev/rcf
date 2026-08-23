import SwiftUI

/// Zones browser: searchable list, create/delete, pull-to-refresh.
/// Usable inside any NavigationStack (`AppShell`) or standalone (`ZoneListView`).
struct ZoneBrowserList: View {
    @Environment(Session.self) private var session
    @State private var model: ZonesViewModel?
    /// Called when a zone row is tapped; nil = navigate via Zone value.
    var onOpenZone: ((Zone) -> Void)? = nil

    var body: some View {
        Group {
            if let model {
                listContent(model: model)
            } else {
                LoadingView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddZoneButton(model: model)
            }
        }
        .task {
            if model == nil {
                model = ZonesViewModel(session: session)
            }
            await model?.loadFirstPage()
        }
    }

    @ViewBuilder
    private func listContent(model: ZonesViewModel) -> some View {
        switch model.state {
        case .loading:
            LoadingView(title: "Loading zones…")
        case .empty:
            VStack(spacing: 16) {
                EmptyState(icon: "globe", title: "No zones", message: model.searchText.isEmpty ? "Add a zone to get started." : "No zones match “\(model.searchText)”.")
            }
        case let .error(message):
            ErrorRetryView(message: message) {
                Task { await model.loadFirstPage() }
            }
        case .loaded:
            List {
                ForEach(model.zones) { zone in
                    Group {
                        if let onOpenZone {
                            Button {
                                onOpenZone(zone)
                            } label: {
                                ZoneRow(zone: zone)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: zone) {
                                ZoneRow(zone: zone)
                            }
                        }
                    }
                    .task { await model.loadMoreIfNeeded(current: zone) }
                }
                .listRowBackground(Color.clear)
            }
            .inkList()
            .refreshable { await model.refresh() }
            .searchable(text: Binding(
                get: { model.searchText },
                set: { model.searchText = $0 }
            ), prompt: "Search zones")
        }
    }
}

/// Standalone zones screen with its own navigation stack.
struct ZoneListView: View {
    @Environment(Session.self) private var session

    var body: some View {
        NavigationStack {
            ZoneBrowserList()
                .navigationTitle("Zones")
                .navigationDestination(for: Zone.self) { zone in
                    ZoneDetailView(zone: zone, session: session)
                }
        }
    }
}

struct ZoneRow: View {
    let zone: Zone

    var statusBadge: Badge.Style {
        switch zone.status {
        case "active": .success
        case "pending": .warning
        default: .danger
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .foregroundStyle(.cfAccent)
                .frame(width: 36, height: 36)
                .background(.cfAccent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(zone.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.cfText)
                HStack(spacing: 6) {
                    Badge(text: zone.status.capitalized, style: statusBadge)
                    Badge(text: zone.plan.name, style: .neutral)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.cfTextTertiary)
        }
        .padding(.vertical, 4)
    }
}

struct AddZoneButton: View {
    let model: ZonesViewModel?
    @State private var showing = false
    @State private var name = ""
    @State private var error: String?
    @State private var creating = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "plus")
        }
        .sheet(isPresented: $showing) {
            NavigationStack {
                Form {
                    TextField("Domain name (e.g. example.com)", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let error {
                        Text(error).foregroundStyle(.cfDanger).font(.footnote)
                    }
                }
                .inkList()
                .navigationTitle("Add Zone")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                    ToolbarItem(placement: .confirmationAction) {
                        AddZoneConfirmButton(model: model, name: name, creating: $creating, showing: $showing, newName: $name, submitError: $error)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

#Preview {
    ZoneListView()
}


/// Extracted toolbar button so @State bindings stay simple.
private struct AddZoneConfirmButton: View {
    let model: ZonesViewModel?
    let name: String
    @Binding var creating: Bool
    @Binding var showing: Bool
    @Binding var newName: String
    @Binding var submitError: String?

    var body: some View {
        if creating {
            ProgressView()
        } else {
            Button("Add") {
                guard let model, !name.isEmpty else { return }
                creating = true
                Task {
                    do {
                        try await model.createZone(name: name)
                        showing = false
                        newName = ""
                        submitError = nil
                    } catch {
                        submitError = (error as? CloudflareError)?.userMessage ?? "Failed"
                    }
                    creating = false
                }
            }
            .disabled(name.isEmpty || creating)
        }
    }
}
