import SwiftUI

/// Full settings: account, appearance, privacy, security, features, about.
struct SettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppLockManager.self) private var lock
    @Environment(ThemeManager.self) private var theme
    @Environment(Session.self) private var session
    @AppStorage("rcf.privacy.maskSensitive") private var maskSensitive = true
    @State private var showProfiles = false
    @State private var confirmSignOut = false

    var body: some View {
        @Bindable var lock = lock
        @Bindable var theme = theme
        NavigationStack {
            List {
                Section("Account") {
                    Button { showProfiles = true } label: {
                        LabeledContent("Profile") { Text(session.profile.label).foregroundStyle(.cfTextSecondary) }
                    }.foregroundStyle(.cfText)
                    if let account = session.accounts.first(where: { $0.id == session.accountId }) ?? session.accounts.first {
                        LabeledContent("Account") { Text(maskSensitive ? Masking.token(account.name) : account.name) }
                    }
                    NavigationLink { MembersView(session: session) } label: { Label("Members", systemImage: "person.2") }
                    Button(role: .destructive) { confirmSignOut = true } label: { Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right") }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $theme.preference) {
                        ForEach(ThemePreference.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Language", selection: .constant("system")) { Text("System Default").tag("system") }
                        .disabled(true)
                }

                Section("Privacy") {
                    Toggle("Mask sensitive data", isOn: $maskSensitive)
                    Text("Masks emails, profile identifiers, and account details on screen.").font(.caption).foregroundStyle(.cfTextSecondary)
                }

                Section("Security") {
                    Toggle("Biometric app lock", isOn: $lock.isEnabled).disabled(!lock.biometricsAvailable)
                    Button { lock.lock() } label: { Label("Lock Now", systemImage: "lock") }.disabled(!lock.isEnabled)
                }

                Section("Features") {
                    NavigationLink { MonitorConfigView() } label: { Label("Monitoring", systemImage: "antenna.radiowaves.left.and.right") }
                    NavigationLink { AISettingsView() } label: { Label("AI Provider", systemImage: "sparkles") }
                }

                Section("About") {
                    NavigationLink { AboutView() } label: { Label("About RCF", systemImage: "info.circle") }
                }
            }
            .inkList()
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { SheetCloseButton() } }
            .sheet(isPresented: $showProfiles) { ProfilePicker() }
            .alert("Sign out?", isPresented: $confirmSignOut) {
                Button("Sign Out", role: .destructive) { auth.signOut(profileOnly: true) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Saved profiles remain on this device.") }
        }
    }
}

#Preview { SettingsView() }
