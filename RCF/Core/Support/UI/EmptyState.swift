import SwiftUI

/// Empty-list / empty-state placeholder (RN `empty-state.tsx`).
struct EmptyState: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.cfTextTertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.cfText)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.cfTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }
}

#Preview {
    EmptyState(icon: "globe", title: "No zones", message: "Add a zone in the Cloudflare dashboard to get started.")
}
