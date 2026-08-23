import SwiftUI

/// Live tail console: stream rows, filter, pause, controls.
struct TailConsoleView: View {
    @State private var model: TailViewModel

    init(accountId: String, script: String, session: Session) {
        _model = State(initialValue: TailViewModel(accountId: accountId, script: script, session: session))
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            switch model.state {
            case .idle, .connecting:
                LoadingView(title: "Connecting to tail…")
            case let .failed(message):
                ErrorRetryView(message: message) {
                    Task { await model.start() }
                }
            case .closed:
                EmptyState(icon: "antenna.radiowaves.left.and.right.slash", title: "Tail stopped", message: "Press Start to stream live events again.")
            case .live:
                eventList
            }
        }
        .navigationTitle("Tail — \(model.script)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            statusDot
            Toggle("", isOn: Binding(
                get: { model.paused },
                set: { model.paused = $0 }
            ))
            .toggleStyle(.button)
            .labelStyle(.iconOnly)
            .help("Pause")
            Spacer()
            if model.state == .live || model.state == .connecting {
                Button("Stop") { model.stop() }
                    .buttonStyle(.borderedProminent)
                    .tint(.cfDanger)
            } else {
                Button("Start") {
                    Task { await model.start() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusDot: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(.cfTextSecondary)
        }
    }

    private var dotColor: Color {
        switch model.state {
        case .live: .cfSuccess
        case .connecting: .cfWarning
        case .failed: .cfDanger
        default: .cfTextTertiary
        }
    }

    private var statusLabel: String {
        switch model.state {
        case .idle: "Idle"
        case .connecting: "Connecting"
        case .live: model.paused ? "Live (paused)" : "Live"
        case .closed: "Stopped"
        case let .failed(message): message
        }
    }

    private var eventList: some View {
        List(model.filteredEvents) { event in
            TailEventRow(event: event)
        }
        .listStyle(.plain)
        .searchable(text: Binding(
            get: { model.filter },
            set: { model.filter = $0 }
        ), prompt: "Filter events")
        .overlay {
            if model.filteredEvents.isEmpty {
                EmptyState(icon: "antenna.radiowaves.left.and.right", title: "Waiting for events", message: "Send requests to your Worker to see live logs.")
            }
        }
    }
}

struct TailEventRow: View {
    let event: TailEvent

    private var timestamp: String {
        guard let ts = event.eventTimestamp else { return "" }
        let date = Date(timeIntervalSince1970: ts / 1000)
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(timestamp)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.cfTextTertiary)
                Badge(text: event.outcomeBadge, style: outcomeStyle)
                Spacer()
            }
            HStack {
                Text(event.title)
                    .font(.caption.weight(.semibold).monospaced())
                Text(event.url ?? "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.cfTextSecondary)
                    .lineLimit(1)
            }
            ForEach(Array(event.logs.keys), id: \.self) { level in
                if let message = event.logs[level] {
                    Text(message)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(logColor(level))
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            ForEach(event.exceptions, id: \.self) { exception in
                Label(exception, systemImage: "exclamationmark.triangle")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.cfDanger)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 3)
    }

    private var outcomeStyle: Badge.Style {
        switch event.outcome {
        case "ok": .success
        case "exception": .danger
        case "canceled": .warning
        default: .neutral
        }
    }

    private func logColor(_ level: TailEvent.LogLevel) -> Color {
        switch level {
        case .error: .cfDanger
        case .warn: .cfWarning
        case .info, .debug: .cfTextTertiary
        default: .cfText
        }
    }
}
