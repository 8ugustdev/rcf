import SwiftUI

/// Ink chrome: themed list/form surfaces + navigation chrome, applied per
/// screen. Adapts automatically to the active palette (Light/Dark/Ink Dark).
///
/// Usage: `List { … }.inkList()` / any container `.inkSurface()`.
extension View {
    /// List/Form on the ink canvas: hides the system grouped background,
    /// paints the palette canvas, themes rows, and forces opaque chrome
    /// (nav/toolbar + sheet background) so iOS 26 glass never shows white.
    /// The presentation/toolbar modifiers are no-ops outside sheets/bars.
    func inkList() -> some View {
        scrollContentBackground(.hidden)
            .background(.cfBackground)
            .listRowBackground(Color.clear)
            .presentationBackground(.cfBackground)
            .toolbarBackground(.cfFooter, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// Themed multiline editor (TextEditor): ink surface instead of the
    /// system white/dark plate.
    func inkEditor() -> some View {
        scrollContentBackground(.hidden)
            .padding(6)
            .background(.cfSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Non-scrolling surface (cards, grids, editor panes).
    func inkSurface() -> some View {
        background(.cfBackground)
    }

    /// Navigation bar tinted to the palette footer (rmote's sheet-chrome
    /// pattern). Apply once per NavigationStack root.
    func inkNavChrome() -> some View {
        toolbarBackground(.cfFooter, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

/// Standard X close button for every sheet's navigation bar.
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cfTextSecondary)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Close")
    }
}

/// Compact value+label stat used by workspace strip, insights, analytics.
struct StatChip: View {
    let value: String
    let label: String
    var tint: Color = .cfText

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.cfTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.cfSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.cfBorder, lineWidth: 0.5)
        }
    }
}

#Preview("StatChip") {
    StatChip(value: "12.4K", label: "requests")
        .padding()
        .inkSurface()
}
