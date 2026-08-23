import SwiftUI

/// Multi-account switcher sheet: switch / add / rename / remove profiles.
struct ProfilePicker: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var renamingProfile: Profile?
    @State private var renameText = ""
    @State private var confirmRemove: Profile?

    var body: some View {
        NavigationStack {
            List {
                ForEach(auth.profiles.profiles) { profile in
                    Button {
                        Task {
                            await auth.switchProfile(profile)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.label)
                                    .foregroundStyle(.cfText)
                                Text(profile.auth.maskedDescription)
                                    .font(.caption)
                                    .foregroundStyle(.cfTextSecondary)
                            }
                            Spacer()
                            if profile.id == auth.profiles.activeProfileId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.cfAccent)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            confirmRemove = profile
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        Button {
                            renamingProfile = profile
                            renameText = profile.label
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    }
                }
            }
            .inkList()
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
            .alert("Remove account?", isPresented: Binding(
                get: { confirmRemove != nil },
                set: { if !$0 { confirmRemove = nil } }
            )) {
                Button("Remove", role: .destructive) {
                    if let profile = confirmRemove {
                        Task {
                            try? auth.profiles.remove(id: profile.id)
                            if auth.profiles.activeProfile == nil {
                                auth.signOut()
                                dismiss()
                            }
                        }
                    }
                    confirmRemove = nil
                }
                Button("Cancel", role: .cancel) { confirmRemove = nil }
            } message: {
                Text("The stored credential for “\(confirmRemove?.label ?? "")” will be deleted from the Keychain.")
            }
            .alert("Rename account", isPresented: Binding(
                get: { renamingProfile != nil },
                set: { if !$0 { renamingProfile = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let profile = renamingProfile, !renameText.isEmpty {
                        try? auth.profiles.rename(id: profile.id, to: renameText)
                    }
                    renamingProfile = nil
                }
                Button("Cancel", role: .cancel) { renamingProfile = nil }
            }
        }
    }
}

#Preview {
    ProfilePicker().environment(AuthViewModel())
}
