import Foundation
import SwiftUI

/// SSL/TLS screen model: mode, always-https, min TLS, cert packs.
@MainActor
@Observable
final class SSLViewModel {
    enum State { case loading, loaded, error(String) }

    let zone: Zone
    let session: Session
    private(set) var state: State = .loading
    private(set) var sslMode = "flexible"
    private(set) var alwaysHTTPS = false
    private(set) var minTLS = "1.2"
    private(set) var certificates: [CertificatePack] = []
    private(set) var busy = false
    private(set) var message: String?

    init(zone: Zone, session: Session) {
        self.zone = zone
        self.session = session
    }

    func load() async {
        state = .loading
        do {
            async let settings = fetchSettings()
            async let packs = fetchCertificates()
            let (mode, https, tls) = try await settings
            sslMode = mode
            alwaysHTTPS = https
            minTLS = tls
            certificates = (try? await packs) ?? []
            state = .loaded
        } catch {
            state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load SSL settings")
        }
    }

    func setSSLMode(_ mode: String) async { await patch("ssl", .string(mode)) { self.sslMode = mode } }
    func setAlwaysHTTPS(_ on: Bool) async { await patch("always_use_https", .string(on ? "on" : "off")) { self.alwaysHTTPS = on } }
    func setMinTLS(_ version: String) async { await patch("min_tls_version", .string(version)) { self.minTLS = version } }

    // MARK: - Internals

    private func fetchSettings() async throws -> (String, Bool, String) {
        let ssl: CloudflareResponse<ZoneSettingValue> = try await session.client.send(CloudflareEndpoint.zoneSetting(zoneId: zone.id, id: "ssl"))
        let https: CloudflareResponse<ZoneSettingValue> = try await session.client.send(CloudflareEndpoint.zoneSetting(zoneId: zone.id, id: "always_use_https"))
        let tls: CloudflareResponse<ZoneSettingValue> = try await session.client.send(CloudflareEndpoint.zoneSetting(zoneId: zone.id, id: "min_tls_version"))
        return (
            ssl.result?.value.displayString ?? "flexible",
            Self.alwaysHTTPSIsOn(https.result?.value),
            tls.result?.value.displayString ?? "1.2"
        )
    }

    /// `always_use_https` uses string `"on"/"off"` in the Cloudflare API; tolerate legacy bool too.
    nonisolated static func alwaysHTTPSIsOn(_ value: JSONValue?) -> Bool {
        switch value {
        case .bool(true), .string("on"): true
        default: false
        }
    }

    private func fetchCertificates() async throws -> [CertificatePack] {
        let response: CloudflareResponse<[CertificatePack]> = try await session.client.send(CloudflareEndpoint.sslCertificatePack(zoneId: zone.id))
        return response.result ?? []
    }

    private func patch(_ id: String, _ value: JSONValue, apply: () -> Void) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let _: CloudflareResponse<ZoneSettingValue> = try await session.client.send(
                CloudflareEndpoint.updateZoneSetting(zoneId: zone.id, id: id, value: value)
            )
            apply()
            message = "Saved"
            Haptics.success()
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Update failed"
        }
    }
}

/// SSL/TLS management screen.
struct SSLView: View {
    @State private var model: SSLViewModel

    init(zone: Zone, session: Session) {
        _model = State(initialValue: SSLViewModel(zone: zone, session: session))
    }

    private let sslModes: [(String, String, String)] = [
        ("off", "Off", "No encryption between visitor and Cloudflare."),
        ("flexible", "Flexible", "Encrypts visitor→Cloudflare only. Not recommended."),
        ("full", "Full", "Encrypts end-to-end; self-signed certs allowed at origin."),
        ("strict", "Full (strict)", "Encrypts end-to-end and validates origin certificates."),
    ]

    private let tlsVersions = ["1.0", "1.1", "1.2", "1.3"]

    var body: some View {
        Group {
            switch model.state {
            case .loading: LoadingView(title: "Loading SSL…")
            case let .error(message): ErrorRetryView(message: message) { Task { await model.load() } }
            case .loaded: form
            }
        }
        .navigationTitle("SSL/TLS")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(sslModes, id: \.0) { mode, title, description in
                    Button {
                        Task { await model.setSSLMode(mode) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .foregroundStyle(.cfText)
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.cfTextSecondary)
                            }
                            Spacer()
                            if model.sslMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.cfAccent)
                            }
                        }
                    }
                    .disabled(model.busy)
                }
            } header: {
                Text("Encryption Mode")
            } footer: {
                if let message = model.message { Text(message) }
            }

            Section("Hardening") {
                Toggle("Always Use HTTPS", isOn: Binding(
                    get: { model.alwaysHTTPS },
                    set: { on in Task { await model.setAlwaysHTTPS(on) } }
                ))
                .disabled(model.busy)
                Picker("Minimum TLS Version", selection: Binding(
                    get: { model.minTLS },
                    set: { v in Task { await model.setMinTLS(v) } }
                )) {
                    ForEach(tlsVersions, id: \.self) { Text("TLS \($0)") }
                }
                .disabled(model.busy)
            }

            Section("Edge Certificates") {
                if model.certificates.isEmpty {
                    Text("No active certificate packs")
                        .foregroundStyle(.cfTextSecondary)
                }
                ForEach(model.certificates) { pack in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Badge(text: pack.status.capitalized, style: .success)
                            if let authority = pack.certificateAuthority {
                                Text(authority).font(.caption).foregroundStyle(.cfTextSecondary)
                            }
                        }
                        if let hosts = pack.hosts, !hosts.isEmpty {
                            Text(hosts.joined(separator: ", "))
                                .font(.caption)
                                .lineLimit(2)
                        }
                        if let expires = pack.validity?.expiresOn {
                            LabeledContent("Expires") { Text(expires) }
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .inkList()
    }
}
