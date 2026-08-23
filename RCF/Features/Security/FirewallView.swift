import SwiftUI

/// Firewall screen with three tabs: Custom Rules (WAF), IP Access, Legacy.
struct FirewallView: View {
    @State private var model: FirewallViewModel
    @State private var tab = 0
    @State private var showingRuleEditor = false
    @State private var editingRule: Ruleset.RulesetRule?
    @State private var showingIPCreator = false
    @State private var confirmDeleteWAF: Ruleset.RulesetRule?
    @State private var confirmDeleteIP: IPAccessRule?
    @State private var confirmDeleteLegacy: FirewallRule?

    init(zone: Zone, session: Session) {
        _model = State(initialValue: FirewallViewModel(zone: zone, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                Text("Custom Rules").tag(0)
                Text("IP Access").tag(1)
                Text("Legacy").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.cfDanger)
                    .padding(.horizontal)
            }

            switch tab {
            case 0: wafTab
            case 1: ipTab
            default: legacyTab
            }
        }
        .navigationTitle("Firewall")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editingRule = nil; showingRuleEditor = true } label: {
                    Image(systemName: tab == 0 ? "plus" : "plus")
                }
            }
        }
        .sheet(isPresented: $showingRuleEditor) {
            RuleEditorSheet(model: model, rule: editingRule)
        }
        .sheet(isPresented: $showingIPCreator) {
            IPAccessCreatorSheet(model: model)
        }
        .task(id: tab) {
            switch tab {
            case 0: await model.loadWAF()
            case 1: await model.loadIP()
            default: await model.loadLegacy()
            }
        }
        .alert("Delete custom rule?", isPresented: Binding(
            get: { confirmDeleteWAF != nil }, set: { if !$0 { confirmDeleteWAF = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let rule = confirmDeleteWAF { Task { await model.deleteWAFRule(rule) } }
                confirmDeleteWAF = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteWAF = nil }
        } message: {
            Text("This rule stops matching traffic immediately.")
        }
    }

    // MARK: - WAF tab

    private var wafTab: some View {
        List {
            if model.loadingTab == .waf {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if model.wafRules.isEmpty {
                EmptyState(icon: "firewall", title: "No custom rules", message: "Create a rule to block, challenge, or skip traffic matching an expression.")
            } else {
                ForEach(model.wafRules) { rule in
                    WAFRuleRow(rule: rule, busy: model.busy)
                        .swipeActions {
                            Button(role: .destructive) {
                                confirmDeleteWAF = rule
                            } label: { Label("Delete", systemImage: "trash") }
                            Button {
                                editingRule = rule
                                showingRuleEditor = true
                            } label: { Label("Edit", systemImage: "pencil") }
                            Button {
                                Task { await model.updateWAFRule(rule, enabled: !rule.enabled) }
                            } label: {
                                Label(rule.enabled ? "Disable" : "Enable", systemImage: rule.enabled ? "pause" : "play")
                            }
                        }
                }
            }
        }
        .inkList()
        .refreshable { await model.loadWAF() }
    }

    // MARK: - IP tab

    private var ipTab: some View {
        List {
            if model.loadingTab == .ip {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if model.ipRules.isEmpty {
                EmptyState(icon: "network", title: "No IP access rules", message: "Block, challenge, or whitelist IPs, ranges, countries, ASNs.")
            } else {
                ForEach(model.ipRules) { rule in
                    IPAccessRow(rule: rule)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await model.deleteIPRule(rule) }
                            } label: { Label("Delete", systemImage: "trash") }
                            Menu {
                                ForEach(["block", "challenge", "whitelist", "js_challenge"], id: \.self) { mode in
                                    Button(mode) {
                                        Task { await model.setIPRuleMode(rule, mode: mode) }
                                    }
                                }
                            } label: { Label("Mode", systemImage: "switch.2") }
                        }
                }
            }
        }
        .inkList()
        .refreshable { await model.loadIP() }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button { showingIPCreator = true } label: { Label("Add IP Rule", systemImage: "plus") }
            }
        }
    }

    // MARK: - Legacy tab

    private var legacyTab: some View {
        List {
            if model.loadingTab == .legacy {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if model.legacyRules.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", title: "No legacy rules", message: "Legacy firewall rules from the old Cloudflare firewall UI.")
            } else {
                ForEach(model.legacyRules) { rule in
                    LegacyRuleRow(rule: rule)
                        .swipeActions {
                            Button(role: .destructive) {
                                confirmDeleteLegacy = rule
                            } label: { Label("Delete", systemImage: "trash") }
                            Button {
                                Task { await model.toggleLegacyRule(rule) }
                            } label: {
                                Label(rule.paused ? "Resume" : "Pause", systemImage: rule.paused ? "play" : "pause")
                            }
                        }
                }
            }
        }
        .inkList()
        .refreshable { await model.loadLegacy() }
        .alert("Delete legacy rule?", isPresented: Binding(
            get: { confirmDeleteLegacy != nil }, set: { if !$0 { confirmDeleteLegacy = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let rule = confirmDeleteLegacy { Task { await model.deleteLegacyRule(rule) } }
                confirmDeleteLegacy = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteLegacy = nil }
        } message: {
            Text("Legacy rule will be removed.")
        }
    }
}

// MARK: - Rows

struct WAFRuleRow: View {
    let rule: Ruleset.RulesetRule
    let busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rule.description ?? "Untitled rule")
                    .font(.body.weight(.medium))
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Badge(text: rule.enabled ? "On" : "Off", style: rule.enabled ? .success : .neutral)
            }
            Text(rule.expression)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.cfTextSecondary)
                .lineLimit(2)
            HStack {
                Badge(text: rule.action.uppercased(), style: .danger)
            }
        }
        .padding(.vertical, 2)
    }
}

struct IPAccessRow: View {
    let rule: IPAccessRule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(rule.configuration.value)
                    .font(.body.weight(.medium).monospaced())
                Spacer()
                Badge(text: rule.mode.uppercased(), style: modeStyle)
            }
            Text("\(rule.configuration.target) • \(rule.notes ?? "no notes")")
                .font(.caption)
                .foregroundStyle(.cfTextSecondary)
        }
        .padding(.vertical, 2)
    }

    private var modeStyle: Badge.Style {
        switch rule.mode {
        case "block": .danger
        case "whitelist": .success
        default: .warning
        }
    }
}

struct LegacyRuleRow: View {
    let rule: FirewallRule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(rule.description ?? "Untitled")
                    .font(.body.weight(.medium))
                Spacer()
                Badge(text: rule.paused ? "Paused" : "Active", style: rule.paused ? .neutral : .success)
            }
            Text(rule.filter.expression)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.cfTextSecondary)
                .lineLimit(2)
            Badge(text: rule.action.uppercased(), style: .danger)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Creators

/// WAF custom rule editor (create or edit).
struct RuleEditorSheet: View {
    let model: FirewallViewModel
    let rule: Ruleset.RulesetRule? // nil = create

    @Environment(\.dismiss) private var dismiss
    @State private var expression = ""
    @State private var action = "block"
    @State private var description = ""
    @State private var submitError: String?

    private let actions = ["block", "managed_challenge", "js_challenge", "log", "skip"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Rule") {
                    TextField("Description", text: $description)
                    Picker("Action", selection: $action) {
                        ForEach(actions, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")) }
                    }
                }
                Section {
                    TextEditor(text: $expression)
                        .font(.system(.caption, design: .monospaced))
                        .inkEditor()
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Expression")
                } footer: {
                    Text(ExpressionValidator.isValid(expression) ? "Balanced ✓" : "Unbalanced parentheses or quotes")
                        .foregroundStyle(ExpressionValidator.isValid(expression) ? .cfSuccess : .cfWarning)
                }
                if let submitError {
                    Section { Text(submitError).foregroundStyle(.cfDanger).font(.footnote) }
                }
            }
            .inkList()
            .navigationTitle(rule == nil ? "New Custom Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                if let rule {
                                    await model.updateWAFRule(rule, action: action, expression: expression, description: description.isEmpty ? nil : description)
                                } else {
                                    await model.createWAFRule(action: action, expression: expression, description: description.isEmpty ? nil : description)
                                }
                                dismiss()
                            }
                        }
                    }
                    .disabled(expression.isEmpty || !ExpressionValidator.isValid(expression))
                }
            }
            .onAppear {
                if let rule {
                    expression = rule.expression
                    action = rule.action
                    description = rule.description ?? ""
                }
            }
        }
    }
}

/// IP access rule creator.
struct IPAccessCreatorSheet: View {
    let model: FirewallViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var targetKind = "ip"
    @State private var value = ""
    @State private var mode = "block"
    @State private var notes = ""

    private let kinds = [("ip", "IP"), ("ip_range", "IP Range"), ("country", "Country"), ("asn", "ASN"), ("continent", "Continent")]
    private let modes = ["block", "challenge", "whitelist", "js_challenge"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Target", selection: $targetKind) {
                    ForEach(kinds, id: \.0) { Text($1).tag($0) }
                }
                TextField(placeholderForKind, text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Mode", selection: $mode) {
                    ForEach(modes, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")) }
                }
                TextField("Notes (optional)", text: $notes)
            }
            .inkList()
            .navigationTitle("New IP Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await model.createIPRule(mode: mode, target: targetKind, value: value, notes: notes.isEmpty ? nil : notes)
                            dismiss()
                        }
                    }
                    .disabled(value.isEmpty)
                }
            }
        }
    }

    private var placeholderForKind: String {
        switch targetKind {
        case "ip": "203.0.113.10"
        case "ip_range": "203.0.113.0/24"
        case "country": "VN (ISO 3166 alpha-2)"
        case "asn": "13335"
        default: "AS / EU / NA"
        }
    }
}
