import SwiftUI

/// Searchable zone picker used by dashboard quick actions.
struct ZonePickerSheet: View {
    let zones: [Zone]
    let onPick: (Zone) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [Zone] {
        search.isEmpty ? zones : zones.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { zone in
                Button {
                    onPick(zone)
                    dismiss()
                } label: {
                    ZoneRow(zone: zone)
                }
            }
            .searchable(text: $search, prompt: "Search zones")
            .navigationTitle("Choose Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
            .overlay {
                if filtered.isEmpty {
                    EmptyState(icon: "globe", title: "No zones", message: "No zones match your search.")
                }
            }
        }
    }
}

#Preview {
    ZonePickerSheet(zones: []) { _ in }
}
