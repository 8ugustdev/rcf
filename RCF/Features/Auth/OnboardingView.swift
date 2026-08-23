import SwiftUI

/// First-launch onboarding: value intro + Get Started (shown once).
struct OnboardingView: View {
    let onComplete: () -> Void

    private struct Slide {
        let icon: String
        let title: String
        let message: String
    }

    private let slides: [Slide] = [
        Slide(icon: "globe", title: "Manage your zones", message: "DNS, SSL, firewall, cache and analytics — everything in your Cloudflare account, native on iOS."),
        Slide(icon: "cube.box", title: "Workers, KV, R2, D1", message: "Inspect scripts, browse namespaces and buckets, run SQL against your D1 databases."),
        Slide(icon: "lock.shield", title: "Your keys stay yours", message: "Tokens are stored in the iOS Keychain. Lock the app with Face ID or a passcode."),
    ]

    @State private var index = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $index) {
                ForEach(slides.indices, id: \.self) { i in
                    VStack(spacing: 20) {
                        Image(systemName: slides[i].icon)
                            .font(.system(size: 64))
                            .foregroundStyle(.cfAccent)
                        Text(slides[i].title)
                            .font(.title2.bold())
                            .foregroundStyle(.cfText)
                        Text(slides[i].message)
                            .font(.body)
                            .foregroundStyle(.cfTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)

            Button {
                if index < slides.count - 1 {
                    withAnimation { index += 1 }
                } else {
                    onComplete()
                }
            } label: {
                Text(index < slides.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(.cfBackground)
    }
}

#Preview {
    OnboardingView {}
}
