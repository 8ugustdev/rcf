import SwiftUI

/// Small pill badge for status display (RN `badge.tsx`).
struct Badge: View {
    let text: String
    var style: Style = .neutral

    enum Style {
        case neutral, success, warning, danger, info

        var foreground: Color {
            switch self {
            case .neutral: .cfBadgeText
            case .success: .cfSuccess
            case .warning: .cfWarning
            case .danger: .cfDanger
            case .info: .cfInfo
            }
        }

        var backgroundOpacity: Double {
            switch self {
            case .neutral: 1.0
            default: 0.15
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(style.foreground)
            .background(
                (style == .neutral ? .cfBadge : style.foreground.opacity(style.backgroundOpacity)),
                in: Capsule()
            )
    }
}

#Preview {
    VStack {
        Badge(text: "Active", style: .success)
        Badge(text: "Paused", style: .warning)
        Badge(text: "PRO", style: .neutral)
    }
}
