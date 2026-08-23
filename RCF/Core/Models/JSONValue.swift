import Foundation

/// Type-erased JSON value for fields the API types loosely (`value`, `data`).
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(bool): try container.encode(bool)
        case let .number(number): try container.encode(number)
        case let .string(string): try container.encode(string)
        case let .array(array): try container.encode(array)
        case let .object(object): try container.encode(object)
        }
    }

    /// String rendering for display (settings values, DNS `data`).
    var displayString: String {
        switch self {
        case .null: "—"
        case let .bool(bool): bool ? "on" : "off"
        case let .number(number):
            number == number.rounded() ? String(Int(number)) : String(number)
        case let .string(string): string
        case let .array(array): array.map(\.displayString).joined(separator: ", ")
        case let .object(object):
            object.map { "\($0)=\($1.displayString)" }.sorted().joined(separator: " ")
        }
    }
}
