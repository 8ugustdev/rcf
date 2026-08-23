import SwiftUI

/// Error display with retry action (RN error retry pattern).
struct ErrorRetryView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.cfWarning)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.cfTextSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

#Preview {
    ErrorRetryView(message: "Failed to load zones.") {}
}
