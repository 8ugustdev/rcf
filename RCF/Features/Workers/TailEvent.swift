import Foundation

/// Decoded tail event (tolerant — CF trace schema with optional everything).
nonisolated struct TailEvent: Sendable, Equatable, Identifiable {
    let id: UUID
    let eventTimestamp: Double?
    let outcome: String
    let scriptName: String?
    let method: String?
    let url: String?
    let status: Int?
    let logs: [LogLevel: String]
    let logOrder: [String]
    let exceptions: [String]
    let coppices: JSONValue?

    struct LogLevel: Hashable, Sendable {
        let raw: String
        init(_ raw: String) { self.raw = raw.lowercased() }
        static let log = LogLevel("log")
        static let error = LogLevel("error")
        static let warn = LogLevel("warn")
        static let info = LogLevel("info")
        static let debug = LogLevel("debug")
    }

    /// Row title for the console.
    var title: String {
        var parts: [String] = []
        if let method { parts.append(method) }
        if let status { parts.append(String(status)) }
        if parts.isEmpty { parts.append(outcome) }
        return parts.joined(separator: " ")
    }

    var outcomeBadge: String {
        switch outcome {
        case "ok": "OK"
        case "exception": "ERROR"
        case "canceled": "CANCELED"
        default: outcome.uppercased()
        }
    }
}

nonisolated enum TailEventDecoder {
    /// Parses one raw trace frame (already UTF-8 text) into a TailEvent; nil for non-JSON frames.
    static func decode(_ text: String) -> TailEvent? {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawEvent.self, from: data) else { return nil }
        return TailEvent(
            id: UUID(),
            eventTimestamp: raw.eventTimestamp,
            outcome: raw.outcome ?? "unknown",
            scriptName: raw.scriptName,
            method: raw.event?.request?.method,
            url: raw.event?.request?.url,
            status: raw.event?.response?.status,
            logs: decodeLogs(raw.logs ?? []),
            logOrder: (raw.logs ?? []).map { levelKey($0.level) },
            exceptions: (raw.exceptions ?? []).map { "\($0.name): \($0.message)" },
            coppices: raw.diagnosticsChannelEvents
        )
    }

    private static func decodeLogs(_ logs: [RawLog]) -> [TailEvent.LogLevel: String] {
        var result: [TailEvent.LogLevel: String] = [:]
        for log in logs {
            let key = TailEvent.LogLevel(levelKey(log.level))
            let message: String
            if let single = log.message.value as? String {
                message = single
            } else if let array = log.message.value as? [Any] {
                message = array.map { item in
                    if let string = item as? String { return string }
                    if let json = try? JSONSerialization.data(withJSONObject: item),
                       let text = String(data: json, encoding: .utf8) { return text }
                    return String(describing: item)
                }.joined(separator: " ")
            } else if let anyValue = log.message.value,
                      let json = try? JSONSerialization.data(withJSONObject: anyValue),
                      let text = String(data: json, encoding: .utf8) {
                message = text
            } else {
                message = String(describing: log.message.value ?? "")
            }
            result[key] = message
        }
        return result
    }

    private static func levelKey(_ level: String?) -> String {
        (level ?? "log").lowercased()
    }

    // Raw tolerant decode structs.
    private struct RawEvent: Decodable {
        let outcome: String?
        let scriptName: String?
        let eventTimestamp: Double?
        let event: RawEventDetail?
        let logs: [RawLog]?
        let exceptions: [RawException]?
        let diagnosticsChannelEvents: JSONValue?

        enum CodingKeys: String, CodingKey {
            case outcome, event, logs, exceptions
            case scriptName = "scriptName"
            case eventTimestamp = "eventTimestamp"
            case diagnosticsChannelEvents = "diagnostics_channel_events"
        }
    }

    private struct RawEventDetail: Decodable {
        let request: RawRequest?
        let response: RawResponse?
    }

    private struct RawRequest: Decodable {
        let method: String?
        let url: String?
    }

    private struct RawResponse: Decodable {
        let status: Int?
    }

    private struct RawLog: Decodable {
        let level: String?
        let message: AnyCodableMessage
    }

    /// `message` may be string, array, or object — keep raw JSONValue-like access.
    private struct AnyCodableMessage: Decodable {
        let value: Any?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else if let array = try? container.decode([AnyDecodable].self) {
                value = array.map(\.value)
            } else if let object = try? container.decode([String: AnyDecodable].self) {
                value = object.mapValues(\.value)
            } else {
                value = nil
            }
        }
    }

    private struct AnyDecodable: Decodable {
        let value: Any

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                value = string
            } else if let number = try? container.decode(Double.self) {
                value = number
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
            } else if let array = try? container.decode([AnyDecodable].self) {
                value = array.map(\.value)
            } else {
                value = (try? container.decode([String: AnyDecodable].self))?.mapValues(\.value) ?? nil
            }
        }
    }

    private struct RawException: Decodable {
        let name: String
        let message: String
    }
}

extension TailEvent.LogLevel: RawRepresentable {
    init?(rawValue: String) { self.init(rawValue) }
    var rawValue: String { raw }
}
