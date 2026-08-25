import SwiftUI

struct AboutView: View {
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    private var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1" }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "cloud.fill").font(.system(size: 54)).foregroundStyle(.cfAccent).accessibilityHidden(true)
                    Text("RCF").font(.largeTitle.bold())
                    Text("Version \(version) (\(build))").foregroundStyle(.cfTextSecondary)
                }.frame(maxWidth: .infinity).padding()
            }
            Section("About") {
                Text("RCF is an unofficial Cloudflare manager and is not affiliated with or endorsed by Cloudflare, Inc.")
                NavigationLink("Privacy") { PrivacyView() }
                Link("Website", destination: URL(string: "https://rcf.8ugust.dev/")!)
            }
            Section("Implementation") {
                Text("Native iOS implementation built with SwiftUI and Apple frameworks; no third-party runtime dependencies.")
                Link("Cloudflare API Documentation", destination: URL(string: "https://developers.cloudflare.com/api/")!)
            }
        }.navigationTitle("About")
        .inkList()
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("Data") { Text("RCF has no analytics or advertising SDK. Cloudflare credentials and AI API keys are stored in the iOS Keychain and are not synced to other devices.") }
            Section("Cloudflare") { Text("Requests are sent directly from your device to the Cloudflare API using the profile you configure.") }
            Section("AI") { Text("AI features are optional. When used, the displayed zone snapshot or activity is sent directly to the OpenAI-compatible provider you configure. RCF does not proxy or retain those requests.") }
            Section("Monitoring") { Text("Monitoring configuration and alert history are stored in the Keychain. Notifications are local and background execution is best-effort.") }
            Section {
                Link("Full privacy policy", destination: URL(string: "https://rcf.8ugust.dev/policy/")!)
            }
        }.navigationTitle("Privacy")
        .inkList()
    }
}
