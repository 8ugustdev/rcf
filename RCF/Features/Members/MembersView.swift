import SwiftUI

nonisolated extension CloudflareEndpoint {
    static func accountMembers(accountId: String, page: Int = 1) -> CloudflareRequest {
        CloudflareRequest(path: "/accounts/\(accountId)/members", query: [.init(name: "page", value: "\(page)"), .init(name: "per_page", value: "50")])
    }
}

struct MembersView: View {
    let session: Session
    @State private var members: [AccountMember] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        Group {
            if loading { LoadingView(title: "Loading members…") }
            else if let errorText { ErrorRetryView(message: errorText) { Task { await load() } } }
            else if members.isEmpty { EmptyState(icon: "person.2", title: "No members", message: "No account members were returned.") }
            else {
                List(members) { member in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(displayName(member)).font(.headline)
                        Text(Masking.email(member.user.email)).font(.caption).foregroundStyle(.cfTextSecondary)
                        HStack {
                            Badge(text: member.status.capitalized, style: member.status == "accepted" ? .success : .warning)
                            Text(member.roles.map(\.name).joined(separator: ", "))
                                .font(.caption2).foregroundStyle(.cfTextTertiary)
                        }
                    }.padding(.vertical, 3)
                }.refreshable { await load() }
            }
        }
        .navigationTitle("Members")
        .task { await load() }
    }

    private func displayName(_ member: AccountMember) -> String {
        let name = [member.user.firstName, member.user.lastName].compactMap { $0 }.joined(separator: " ")
        return name.isEmpty ? member.user.email : name
    }

    private func load() async {
        loading = true; errorText = nil; defer { loading = false }
        guard let accountId = session.accountId else { errorText = "No account selected"; return }
        do { (members, _) = try await session.client.sendList(CloudflareEndpoint.accountMembers(accountId: accountId)) }
        catch { errorText = error.localizedDescription }
    }
}
