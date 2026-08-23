import SwiftUI

/// Section title with optional trailing action (RN `section-header.tsx`).
struct SectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cfTextSecondary)
            Spacer()
            trailing
        }
    }
}

#Preview {
    SectionHeader("DNS RECORDS") {
        Button("Add") {}
    }
}
