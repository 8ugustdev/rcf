import SwiftUI

/// Zone settings: editable subset + read-only display of the rest.
struct ZoneSettingsView: View {
    let model: ZoneDetailViewModel

    /// Setting ids surfaced with editors (RN parity subset).
    private static let sslModes = ["off", "flexible", "full", "strict"]
    private static let minTLS = ["1.0", "1.1", "1.2", "1.3"]
    private static let securityLevels = ["off", "essentially_off", "low", "medium", "high", "under_attack"]
    private static let cacheLevels = ["off", "basic", "simplified", "aggressive"]

    var body: some View {
        Form {
            editableSection
            readOnlySection
        }
        .inkList()
        .navigationTitle("Zone Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var editableSection: some View {
        Section("Editable") {
            Picker("SSL/TLS mode", selection: binding("ssl", allowed: Self.sslModes)) {
                ForEach(Self.sslModes, id: \.self) { Text($0.capitalized) }
            }
            Picker("Minimum TLS", selection: binding("min_tls_version", allowed: Self.minTLS)) {
                ForEach(Self.minTLS, id: \.self) { Text("TLS \($0)") }
            }
            Picker("Security level", selection: binding("security_level", allowed: Self.securityLevels)) {
                ForEach(Self.securityLevels, id: \.self) { Text(label(for: $0)) }
            }
            Picker("Cache level", selection: binding("cache_level", allowed: Self.cacheLevels)) {
                ForEach(Self.cacheLevels, id: \.self) { Text($0.capitalized) }
            }
            Toggle("Always Use HTTPS", isOn: boolBinding("always_use_https"))
            Toggle("Brotli", isOn: boolBinding("brotli"))
            Toggle("HTTP/2", isOn: boolBinding("http2"))
            Toggle("HTTP/3 (QUIC)", isOn: boolBinding("http3"))
            Toggle("0-RTT Connection Resumption", isOn: boolBinding("0_rtT".lowercased()))
        }
    }

    private var readOnlySection: some View {
        Section("Read-only") {
            ForEach(sortedOtherSettingIds, id: \.self) { id in
                LabeledContent(displayName(for: id)) {
                    Text(model.settings[id]?.displayString ?? "—")
                        .foregroundStyle(.cfTextSecondary)
                }
            }
        }
    }

    /// Ids we render editors for.
    private var editedIds: Set<String> {
        ["ssl", "min_tls_version", "security_level", "cache_level", "always_use_https", "brotli", "http2", "http3", "0rtt", "0-rtt", "development_mode"]
    }

    private var sortedOtherSettingIds: [String] {
        model.settings.keys
            .filter { !editedIds.contains($0) }
            .sorted()
            .prefix(40) // keep the list sane — CF returns dozens of zone settings
            .map { $0 }
    }

    private func binding(_ id: String, allowed: [String]) -> Binding<String> {
        Binding(
            get: {
                if case let .string(value)? = model.settings[id] { return value }
                return model.settings[id]?.displayString ?? allowed.first ?? ""
            },
            set: { newValue in
                Task { await model.setSetting(id, value: .string(newValue)) }
            }
        )
    }

    private func boolBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { model.settings[id] == .bool(true) },
            set: { on in Task { await model.setSetting(id, value: .bool(on)) } }
        )
    }

    private func displayName(for id: String) -> String {
        id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func label(for level: String) -> String {
        switch level {
        case "essentially_off": "Essentially Off"
        case "under_attack": "Under Attack"
        default: level.capitalized
        }
    }
}
