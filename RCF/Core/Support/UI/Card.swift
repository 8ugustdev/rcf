import SwiftUI

/// Rounded surface card (SwiftUI port of RN `components/ui/card.tsx`).
struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.cfSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.cfBorder, lineWidth: 1)
            )
    }
}

#Preview {
    Card {
        Text("Zone example.com")
    }
    .padding()
}
