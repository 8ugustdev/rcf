import SwiftUI

/// Settings-style row: icon, title, optional subtitle/value, trailing content (RN `menu-item.tsx`).
struct MenuItem<Destination: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var iconColor: Color = .cfAccent
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.cfText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.cfTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cfTextTertiary)
            }
            .padding(.vertical, 10)
        }
    }
}

/// Non-navigating menu row with a tap action.
struct MenuActionRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var iconColor: Color = .cfAccent
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(role == .destructive ? .cfDanger : .cfText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.cfTextSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cfTextTertiary)
            }
            .padding(.vertical, 10)
        }
    }
}

#Preview {
    List {
        MenuItem(icon: "globe", title: "example.com", subtitle: "Active", destination: { Text("Zone") })
        MenuActionRow(icon: "trash", title: "Delete", iconColor: .cfDanger, role: .destructive) {}
    }
}
