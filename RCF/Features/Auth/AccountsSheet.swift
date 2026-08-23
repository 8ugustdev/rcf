import SwiftUI

/// Account selector for tokens that span multiple Cloudflare accounts.
struct AccountsSheet: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let session = auth.session {
                    ForEach(session.accounts) { account in
                        Button {
                            Task {
                                await auth.switchAccount(id: account.id)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .foregroundStyle(.cfText)
                                    Text(Masking.maskAccountID(account.id))
                                        .font(.caption)
                                        .foregroundStyle(.cfTextSecondary)
                                }
                                Spacer()
                                if account.id == session.accountId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.cfAccent)
                                }
                            }
                        }
                    }
                }
            }
            .inkList()
            .navigationTitle("Choose Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SheetCloseButton()
                }
            }
            .overlay {
                if auth.session?.accounts.isEmpty != false {
                    EmptyState(icon: "person.2", title: "No accounts", message: "This credential has no account access.")
                }
            }
        }
    }
}

extension Masking {
    /// Account ids get a light mask: first 6 chars.
    static func maskAccountID(_ id: String) -> String {
        id.count <= 6 ? id : "\(id.prefix(6))••••"
    }
}

#Preview {
    AccountsSheet().environment(AuthViewModel())
}
