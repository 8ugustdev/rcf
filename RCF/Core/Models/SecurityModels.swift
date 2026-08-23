import Foundation

/// Firewall / WAF / ruleset DTOs.

nonisolated struct FirewallRule: Codable, Sendable, Identifiable {
    let id: String
    var paused: Bool
    var description: String?
    var action: String
    var priority: Int?
    var filter: FirewallFilter
    let createdOn: String?
    let modifiedOn: String?

    struct FirewallFilter: Codable, Sendable {
        let id: String?
        var expression: String
        var paused: Bool?
        var description: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, paused, description, action, priority, filter
        case createdOn = "created_on"
        case modifiedOn = "modified_on"
    }
}

nonisolated struct IPAccessRule: Codable, Sendable, Identifiable {
    let id: String
    let notes: String?
    let allowedModes: [String]
    let mode: String
    let configuration: Configuration
    let scope: Scope?
    let createdOn: String?
    let modifiedOn: String?

    struct Configuration: Codable, Sendable {
        let target: String
        let value: String
    }

    struct Scope: Codable, Sendable {
        let id: String
        let name: String?
        let type: String
    }

    enum CodingKeys: String, CodingKey {
        case id, notes, allowedModes = "allowed_modes", mode, configuration, scope
        case createdOn = "created_on"
        case modifiedOn = "modified_on"
    }
}

/// WAF custom ruleset entrypoint representation.
nonisolated struct Ruleset: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let kind: String
    let phase: String?
    let version: String?
    let rules: [RulesetRule]?
    let lastUpdater: String?

    struct RulesetRule: Codable, Sendable, Identifiable {
        let id: String
        let version: String?
        var action: String
        var actionParameters: JSONValue?
        var expression: String
        var description: String?
        var enabled: Bool
        let ref: String?
        let lastUpdatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, version, action, expression, description, enabled, ref
            case actionParameters = "action_parameters"
            case lastUpdatedAt = "last_updated_at"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, description, kind, phase, version, rules
        case lastUpdater = "last_updated"
    }
}
