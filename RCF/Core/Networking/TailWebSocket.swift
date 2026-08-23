import Foundation

/// URLSessionWebSocketTask wrapper for Cloudflare trace-v1 tails.
/// Streams decoded TailEvents; handles binary frames (UTF-8 JSON, optional gzip).
nonisolated final class TailWebSocket {
    enum State: Sendable, Equatable {
        case idle, connecting, live, closed, failed(String)
    }

    private let url: URL
    private let session: URLSession
    private nonisolated(unsafe) var task: URLSessionWebSocketTask?
    private nonisolated(unsafe) var continuation: AsyncStream<TailEvent>.Continuation?
    private nonisolated(unsafe) var stateContinuation: AsyncStream<State>.Continuation?
    private let decodeQueue = DispatchQueue(label: "rcf.tail.decode", qos: .userInitiated)

    init(url: URL) {
        self.url = url
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// Starts the socket; yields events until stop() or error.
    func events() -> AsyncStream<TailEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.connect()
        }
    }

    /// Connection state updates.
    var states: AsyncStream<State> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
        }
    }

    private func connect() {
        setState(.connecting)
        let task = session.webSocketTask(with: url, protocols: ["trace-v1"])
        self.task = task
        task.resume()
        setState(.live) // URLSession WS has no open callback; first frame confirms
        receiveLoop()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                self.handle(message)
                self.receiveLoop()
            case let .failure(error):
                self.setState(.failed(error.localizedDescription))
                self.finish()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(frameData):
            data = frameData
        @unknown default:
            data = nil
        }
        guard let data else { return }
        decodeQueue.async { [continuation] in
            // Binary frames may be gzipped (0x1f8b); decode off main thread.
            guard let text = try? Gzip.decodeFrame(data),
                  let event = TailEventDecoder.decode(text) else { return }
            continuation?.yield(event)
        }
    }

    /// Cancels the socket. The caller deletes the tail session via the API.
    func stop() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        setState(.closed)
        finish()
    }

    private func setState(_ state: State) {
        stateContinuation?.yield(state)
    }

    private func finish() {
        continuation?.finish()
        stateContinuation?.finish()
        continuation = nil
        stateContinuation = nil
    }

    deinit {
        task?.cancel()
    }
}
