import SwiftUI

/// Environment action to open the command palette from any depth of the
/// navigation stack (buttons in detail views can't reach the shell's sheet).
@MainActor
@Observable
final class PaletteTrigger {
    let open: () -> Void
    init(open: @escaping () -> Void) {
        self.open = open
    }
}

private struct PaletteTriggerKey: EnvironmentKey {
    @MainActor
    static let defaultValue: PaletteTrigger? = nil
}

extension EnvironmentValues {
    /// Non-nil inside the app shell; opens the global command palette.
    var paletteTrigger: PaletteTrigger? {
        get { self[PaletteTriggerKey.self] }
        set { self[PaletteTriggerKey.self] = newValue }
    }
}

/// Purge-by-URL flow used by the palette command (typed URL list → purge).
struct PurgeURLSheet: View {
    let zone: Zone
    let session: Session

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var submitting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
            .inkEditor()
                        .frame(minHeight: 120)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("URLs (one per line)")
                } footer: {
                    Text("Full URLs on \(zone.name), e.g. https://\(zone.name)/style.css")
                }
                if let message {
                    Text(message).foregroundStyle(.cfDanger)
                }
            }
            .inkList()
            .navigationTitle("Purge URLs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton() }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("Purge") {
                            Task { await purge() }
                        }
                        .disabled(urls.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var urls: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func purge() async {
        submitting = true
        defer { submitting = false }
        do {
            let _: CloudflareResponse<NullResult> = try await session.client.send(
                try CloudflareEndpoint.purgeURLs(zoneId: zone.id, urls: urls)
            )
            Haptics.success()
            dismiss()
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Purge failed"
            Haptics.error()
        }
    }
}
