import SwiftUI

/// Centered progress indicator with optional label (RN `loading.tsx`).
struct LoadingView: View {
    var title: String?

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            if let title {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.cfTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoadingView(title: "Loading zones…")
}
