import SwiftUI

/// Email routing screen: settings, DNS records, rules + catch-all, destinations.
struct EmailRoutingView: View {
    @State private var model: EmailRoutingViewModel
    @State private var showingRuleEditor = false
    @State private var editingRule: EmailRoutingRule?
    @State private var showingCatchAllEditor = false
    @State private var showingDisableConfirm = false
    @State private var confirmDelete: EmailRoutingRule?

    init(zone: Zone, session: Session) {
        _model = State(initialValue: EmailRoutingViewModel(zone: zone, session: session))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading: LoadingView(title: "Loading email routing…")
            case .notConfigured: notConfigured
            case let .error(message): ErrorRetryView(message: message) { Task { await model.loadAll() } }
            case .loaded: content
            }
        }
        .navigationTitle("Email Routing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadAll() }
        .sheet(isPresented: $showingRuleEditor) {
            EmailRuleEditorSheet(model: model, rule: editingRule)
        }
        .sheet(isPresented: $showingCatchAllEditor) {
            CatchAllEditorSheet(model: model)
        }
        .alert("Disable email routing?", isPresented: $showingDisableConfirm) {
            Button("Disable", role: .destructive) { Task { await model.disable() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cloudflare will stop processing email for this zone. MX records may be removed.")
        }
        .alert("Delete rule?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let rule = confirmDelete { Task { await model.deleteRule(rule) } }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Rule “\(confirmDelete?.name ?? "")” will stop matching immediately.")
        }
    }

    private var notConfigured: some View {
        VStack(spacing: 16) {
            EmptyState(icon: "envelope.badge", title: "Email routing not configured", message: "Enable Cloudflare email routing for this zone to forward mail to destinations.")
            Button("Enable Email Routing") {
                Task { await model.enable() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy)
        }
    }

    private var content: some View {
        List {
            settingsSection
            if let routingSettings = model.settings, routingSettings.enabled, routingSettings.status != "ready" {
                dnsSection
            }
            rulesSection
            catchAllSection
            destinationsSection
        }
        .inkList()
        .refreshable { await model.loadAll() }
    }

    private var settingsSection: some View {
        Section {
            if let routingSettings = model.settings {
                LabeledContent("Status") {
                    Badge(text: routingSettings.status.capitalized, style: routingSettings.enabled ? .success : .neutral)
                }
                LabeledContent("Enabled") {
                    Toggle("", isOn: Binding(
                        get: { routingSettings.enabled },
                        set: { on in
                            if on { Task { await model.enable() } } else { showingDisableConfirm = true }
                        }
                    ))
                    .labelsHidden()
                }
                .disabled(model.busy)
            }
            if let message = model.message {
                Text(message).font(.footnote).foregroundStyle(.cfDanger)
            }
        } header: {
            Text("Settings")
        }
    }

    private var dnsSection: some View {
        Section {
            ForEach(Array(model.dnsRecords.enumerated()), id: \.offset) { _, record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(record.type)
                            .font(.caption.bold().monospaced())
                            .foregroundStyle(.cfInfo)
                        Text(record.name)
                            .font(.caption)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = "\(record.name) \(record.priority.map { "\($0) " } ?? "")\(record.content)"
                            Haptics.light()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    Text(record.content)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.cfTextSecondary)
                }
            }
        } header: {
            Text("Required DNS Records")
        } footer: {
            Text("Add these at your registrar (or via the DNS tab) for routing to activate.")
        }
    }

    private var rulesSection: some View {
        Section {
            if model.rules.isEmpty {
                Text("No custom rules")
                    .foregroundStyle(.cfTextSecondary)
            }
            ForEach(model.rules) { rule in
                EmailRuleRow(rule: rule, masked: false)
                    .swipeActions {
                        Button(role: .destructive) {
                            confirmDelete = rule
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            editingRule = rule
                            showingRuleEditor = true
                        } label: { Label("Edit", systemImage: "pencil") }
                        Button {
                            Task { await model.toggleRule(rule) }
                        } label: {
                            Label(rule.enabled ? "Disable" : "Enable", systemImage: rule.enabled ? "pause" : "play")
                        }
                    }
            }
        } header: {
            Text("Rules")
        } footer: {
            HStack {
                Text("Matchers and actions in priority order.")
                Spacer()
                Button("Add Rule") {
                    editingRule = nil
                    showingRuleEditor = true
                }
                .font(.footnote.weight(.semibold))
            }
        }
    }

    private var catchAllSection: some View {
        Section {
            if let catchAll = model.catchAll {
                EmailRuleRow(rule: catchAll, masked: false)
                Toggle("Enabled", isOn: Binding(
                    get: { catchAll.enabled },
                    set: { _ in Task { await model.toggleCatchAll() } }
                ))
                .disabled(model.busy)
                Button("Edit Catch-All Action") {
                    showingCatchAllEditor = true
                }
            }
        } header: {
            Text("Catch-All")
        }
    }

    private var destinationsSection: some View {
        Section {
            ForEach(model.destinations) { destination in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Masking.email(destination.email))
                        if destination.verified == nil {
                            Text("Pending verification")
                                .font(.caption)
                                .foregroundStyle(.cfWarning)
                        }
                    }
                    Spacer()
                    if destination.verified != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.cfSuccess)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await model.deleteDestination(destination) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            AddDestinationRow(model: model)
        } header: {
            Text("Destination Addresses")
        } footer: {
            Text("Account-wide. New destinations receive a verification email before use.")
        }
    }
}

struct EmailRuleRow: View {
    let rule: EmailRoutingRule
    let masked: Bool

    var matcherSummary: String {
        if let matcher = rule.matchers.first {
            if matcher.type == "all" { return "All addresses" }
            return "To: \(masked ? Masking.email(matcher.value ?? "") : matcher.value ?? "")"
        }
        return "—"
    }

    var actionSummary: String {
        guard let action = rule.actions.first else { return "—" }
        switch action.type {
        case "forward":
            let joined = action.value.map { masked ? Masking.email($0) : $0 }.joined(separator: ", ")
            return "Forward → \(joined)"
        case "worker":
            return "Worker → \(action.value.first ?? "")"
        default:
            return "Drop"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(rule.name ?? "Untitled")
                    .font(.body.weight(.medium))
                Spacer()
                Badge(text: rule.enabled ? "On" : "Off", style: rule.enabled ? .success : .neutral)
            }
            Text(matcherSummary)
                .font(.caption)
                .foregroundStyle(.cfTextSecondary)
            Text(actionSummary)
                .font(.caption)
                .foregroundStyle(.cfTextSecondary)
        }
        .padding(.vertical, 2)
    }
}

struct AddDestinationRow: View {
    let model: EmailRoutingViewModel
    @State private var email = ""
    @State private var adding = false

    var body: some View {
        HStack {
            TextField("destination@example.com", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") {
                adding = true
                Task {
                    await model.addDestination(email: email)
                    email = ""
                    adding = false
                }
            }
            .disabled(!email.contains("@") || adding)
        }
    }
}

/// Rule editor: matcher (literal or catch-all not offered here), actions.
struct EmailRuleEditorSheet: View {
    let model: EmailRoutingViewModel
    let rule: EmailRoutingRule? // nil = create

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var matcherAddress = ""
    @State private var actionType = "forward"
    @State private var selectedDestinations = Set<String>()
    @State private var workerScript = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Name", text: $name)
                    TextField("Match address (user@\(model.zone.name))", text: $matcherAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section("Action") {
                    Picker("Type", selection: $actionType) {
                        Text("Forward").tag("forward")
                        Text("Worker").tag("worker")
                        Text("Drop").tag("drop")
                    }
                    if actionType == "forward" {
                        ForEach(model.verifiedDestinations) { destination in
                            Button {
                                if selectedDestinations.contains(destination.email) {
                                    selectedDestinations.remove(destination.email)
                                } else {
                                    selectedDestinations.insert(destination.email)
                                }
                            } label: {
                                HStack {
                                    Text(destination.email)
                                        .foregroundStyle(.cfText)
                                    Spacer()
                                    if selectedDestinations.contains(destination.email) {
                                        Image(systemName: "checkmark").foregroundStyle(.cfAccent)
                                    }
                                }
                            }
                        }
                        if model.verifiedDestinations.isEmpty {
                            Text("No verified destinations — add one below first.")
                                .font(.footnote)
                                .foregroundStyle(.cfTextSecondary)
                        }
                    } else if actionType == "worker" {
                        TextField("Worker script name", text: $workerScript)
                            .textInputAutocapitalization(.never)
                    }
                }
            }
            .inkList()
            .navigationTitle(rule == nil ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear { populate() }
        }
    }

    private var isValid: Bool {
        guard !matcherAddress.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch actionType {
        case "forward": return !selectedDestinations.isEmpty
        case "worker": return !workerScript.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    private func populate() {
        if let rule {
            name = rule.name ?? ""
            matcherAddress = rule.matchers.first?.value ?? ""
            if let action = rule.actions.first {
                actionType = action.type
                if action.type == "forward" {
                    selectedDestinations = Set(action.value)
                } else if action.type == "worker" {
                    workerScript = action.value.first ?? ""
                }
            }
        }
    }

    private func save() {
        let action: EmailRoutingRule.Action
        switch actionType {
        case "forward": action = .forward(Array(selectedDestinations))
        case "worker": action = .worker(workerScript.trimmingCharacters(in: .whitespaces))
        default: action = .drop()
        }
        let draft = EmailRoutingRule(
            id: rule?.id,
            name: name.isEmpty ? matcherAddress : name,
            enabled: rule?.enabled ?? true,
            priority: rule?.priority ?? 0,
            matchers: [.literal(matcherAddress.trimmingCharacters(in: .whitespaces))],
            actions: [action]
        )
        Task {
            await model.saveRule(draft, isNew: rule == nil)
            dismiss()
        }
    }
}

/// Catch-all action editor.
struct CatchAllEditorSheet: View {
    let model: EmailRoutingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var actionType = "drop"
    @State private var selectedDestinations = Set<String>()
    @State private var workerScript = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Catch-All Action") {
                    Picker("Type", selection: $actionType) {
                        Text("Drop").tag("drop")
                        Text("Forward").tag("forward")
                        Text("Worker").tag("worker")
                    }
                    if actionType == "forward" {
                        ForEach(model.verifiedDestinations) { destination in
                            Toggle(destination.email, isOn: Binding(
                                get: { selectedDestinations.contains(destination.email) },
                                set: { on in
                                    if on { selectedDestinations.insert(destination.email) }
                                    else { selectedDestinations.remove(destination.email) }
                                }
                            ))
                        }
                    } else if actionType == "worker" {
                        TextField("Worker script name", text: $workerScript)
                            .textInputAutocapitalization(.never)
                    }
                }
            }
            .inkList()
            .navigationTitle("Catch-All")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if actionType == "worker" {
                                await model.updateCatchAll(actionType: "worker", destinations: [workerScript])
                            } else {
                                await model.updateCatchAll(actionType: actionType, destinations: Array(selectedDestinations))
                            }
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if let action = model.catchAll?.actions.first {
                    actionType = action.type == "forward" && action.value.isEmpty ? "drop" : action.type
                    if action.type == "forward" { selectedDestinations = Set(action.value) }
                    if action.type == "worker" { workerScript = action.value.first ?? "" }
                }
            }
        }
    }
}
