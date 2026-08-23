import Foundation
import SwiftUI

/// Live tail console model: create tail → WS stream → ring buffer (500).
@MainActor
@Observable
final class TailViewModel {
    enum State: Equatable { case idle, connecting, live, closed, failed(String) }

    let accountId: String
    let script: String
    let session: Session

    private(set) var state: State = .idle
    private(set) var events: [TailEvent] = []
    var paused = false
    var filter = ""

    private var socket: TailWebSocket?
    private var streamTask: Task<Void, Never>?
    private var activeTailId: String?

    static let bufferLimit = 500

    init(accountId: String, script: String, session: Session) {
        self.accountId = accountId
        self.script = script
        self.session = session
    }

    var filteredEvents: [TailEvent] {
        guard !filter.isEmpty else { return events }
        let needle = filter.lowercased()
        return events.filter { event in
            event.url?.lowercased().contains(needle) == true
                || event.logs.values.contains { $0.lowercased().contains(needle) }
                || event.exceptions.contains { $0.lowercased().contains(needle) }
                || event.outcome.lowercased().contains(needle)
        }
    }

    func start() async {
        guard state != .live, state != .connecting else { return }
        state = .connecting
        do {
            // 1. Create tail session (signed short-lived URL).
            let response: CloudflareResponse<WorkerTail> = try await session.client.send(
                CloudflareEndpoint.createWorkerTail(accountId: accountId, script: script)
            )
            guard let tail = response.result else { throw CloudflareError.emptyResult }
            activeTailId = tail.id

            // 2. Connect WS + consume stream.
            let socket = TailWebSocket(url: tail.url)
            self.socket = socket
            let stream = socket.events()
            state = .live
            streamTask = Task { [weak self] in
                for await event in stream {
                    guard let self, !Task.isCancelled else { break }
                    self.append(event)
                }
            }
        } catch let error as CloudflareError {
            // 100311: assets-only worker cannot be tailed.
            if case let .api(code, message, _) = error, code == 100311 {
                state = .failed("This Worker serves static assets only — no code to tail.")
            } else {
                state = .failed(error.userMessage)
            }
        } catch {
            state = .failed("Failed to start tail")
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        // Parity: delete the tail session server-side (best-effort; tailId from create).
        if let tailId = activeTailId, !tailId.isEmpty {
            let accountId = self.accountId, script = self.script, session = self.session
            Task {
                let _: CloudflareResponse<NullResult>? = try? await session.client.send(
                    CloudflareEndpoint.deleteWorkerTail(accountId: accountId, script: script, tailId: tailId)
                )
            }
        }
        socket?.stop()
        socket = nil
        state = .closed
    }

    private func append(_ event: TailEvent) {
        guard !paused else { return }
        events.insert(event, at: 0)
        if events.count > Self.bufferLimit {
            events.removeLast(events.count - Self.bufferLimit)
        }
    }
}
