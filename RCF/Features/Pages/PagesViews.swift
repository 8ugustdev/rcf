import SwiftUI

/// Pages projects list + detail (deployments, domains) + delete.
struct PagesProjectsView: View {
    @Environment(Session.self) private var session
    @State private var projects: [PagesProject] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var confirmDelete: PagesProject?

    var body: some View {
        Group {
            if loading {
                LoadingView(title: "Loading projects…")
            } else if let errorText {
                ErrorRetryView(message: errorText) { Task { await load() } }
            } else if projects.isEmpty {
                EmptyState(icon: "doc.append", title: "No Pages projects", message: "Deploy a site with Cloudflare Pages.")
            } else {
                List {
                    ForEach(projects) { project in
                        NavigationLink {
                            PagesProjectDetail(session: session, project: project)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                if let subdomain = project.subdomain {
                                    Text("\(subdomain).pages.dev")
                                        .font(.caption)
                                        .foregroundStyle(.cfTextSecondary)
                                }
                                HStack(spacing: 6) {
                                    if let deployment = project.latestDeployment {
                                        Badge(text: deployment.environment ?? "production", style: .info)
                                    }
                                    if let branch = project.productionBranch {
                                        Text(branch).font(.caption2).foregroundStyle(.cfTextTertiary)
                                    }
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { confirmDelete = project } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .inkList()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Pages")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete project?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete Forever", role: .destructive) {
                if let project = confirmDelete {
                    Task {
                        if let accountId = session.accountId {
                            let _: CloudflareResponse<NullResult>? = try? await session.client.send(
                                CloudflareEndpoint.deletePagesProject(accountId: accountId, name: project.name)
                            )
                        }
                        projects.removeAll { $0.id == project.id }
                    }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Project “\(confirmDelete?.name ?? "")” and its deployments will be removed.")
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        errorText = nil
        defer { loading = false }
        guard let accountId = session.accountId else { return }
        do {
            let (list, _): ([PagesProject], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.pagesProjects(accountId: accountId)
            )
            projects = list
        } catch {
            errorText = (error as? CloudflareError)?.userMessage ?? "Failed to load projects"
        }
    }
}

struct PagesProjectDetail: View {
    let session: Session
    let project: PagesProject

    @State private var deployments: [PagesDeployment] = []
    @State private var loadingDeployments = true

    var body: some View {
        List {
            Section("Project") {
                LabeledContent("Name") { Text(project.name) }
                if let subdomain = project.subdomain {
                    LabeledContent("URL") {
                        Link("\(subdomain).pages.dev", destination: URL(string: "https://\(subdomain).pages.dev")!)
                    }
                }
                if let branch = project.productionBranch {
                    LabeledContent("Production branch") { Text(branch) }
                }
                if let domains = project.domains, !domains.isEmpty {
                    LabeledContent("Domains") {
                        Text(domains.joined(separator: ", "))
                    }
                }
            }

            Section("Deployments") {
                if loadingDeployments {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if deployments.isEmpty {
                    Text("No deployments").foregroundStyle(.cfTextSecondary)
                }
                ForEach(deployments) { deployment in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deployment.id.prefix(8))
                                .font(.caption.monospaced())
                            if let created = deployment.createdOn {
                                Text(created.prefix(16).replacingOccurrences(of: "T", with: " "))
                                    .font(.caption2)
                                    .foregroundStyle(.cfTextTertiary)
                            }
                        }
                        Spacer()
                        Badge(text: deployment.environment ?? "production", style: .info)
                        if let stage = deployment.latestStage {
                            Badge(text: stage.status ?? stage.name ?? "—", style: stage.status == "success" ? .success : .warning)
                        }
                    }
                }
            }
        }
        .inkList()
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let accountId = session.accountId else { return }
            if let (list, _): ([PagesDeployment], ResultInfo?) = try? await session.client.sendList(
                CloudflareEndpoint.pagesDeployments(accountId: accountId, projectName: project.name)
            ) {
                deployments = list
            }
            loadingDeployments = false
        }
    }
}
