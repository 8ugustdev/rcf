import Foundation

/// User, account, and zone DTOs (mirror RN `services/types.ts`).

nonisolated struct CloudflareUser: Codable, Sendable, Identifiable {
    let id: String
    let email: String
    let username: String?
    let firstName: String?
    let lastName: String?
    let telephone: String?
    let country: String?
    let organizations: [JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id, email, username, telephone, country, organizations
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

nonisolated struct Account: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let settings: AccountSettings?

    struct AccountSettings: Codable, Sendable {
        let enforceTwofactor: Bool?
        enum CodingKeys: String, CodingKey {
            case enforceTwofactor = "enforce_twofactor"
        }
    }
}

nonisolated struct AccountMember: Codable, Sendable, Identifiable {
    let id: String
    let user: MemberUser
    let status: String
    let roles: [Role]

    struct MemberUser: Codable, Sendable {
        let id: String
        let email: String
        let firstName: String?
        let lastName: String?
        enum CodingKeys: String, CodingKey {
            case id, email
            case firstName = "first_name"
            case lastName = "last_name"
        }
    }

    struct Role: Codable, Sendable {
        let id: String
        let name: String
        let description: String?
    }
}

nonisolated struct Zone: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let paused: Bool
    let type: String
    let developmentMode: Int
    let nameServers: [String]
    let originalNameServers: [String]?
    let originalRegistrar: String?
    let modifiedOn: String?
    let createdOn: String?
    let activatedOn: String?
    let plan: ZonePlan
    let account: ZoneAccount

    struct ZonePlan: Codable, Sendable, Hashable {
        let id: String
        let name: String
        let price: Double?
        let currency: String?
        let frequency: String?
        let isSubscribed: Bool?
        enum CodingKeys: String, CodingKey {
            case id, name, price, currency, frequency
            case isSubscribed = "is_subscribed"
        }
    }

    struct ZoneAccount: Codable, Sendable, Hashable {
        let id: String
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, paused, type, plan, account
        case developmentMode = "development_mode"
        case nameServers = "name_servers"
        case originalNameServers = "original_name_servers"
        case originalRegistrar = "original_registrar"
        case modifiedOn = "modified_on"
        case createdOn = "created_on"
        case activatedOn = "activated_on"
    }
}

/// One zone setting (e.g. `ssl`, `cache_level`) — value is loosely typed.
nonisolated struct ZoneSettingValue: Codable, Sendable {
    let id: String
    let value: JSONValue
    let editable: Bool
    let modifiedOn: String?

    enum CodingKeys: String, CodingKey {
        case id, value, editable
        case modifiedOn = "modified_on"
    }
}

nonisolated struct PageRule: Codable, Sendable, Identifiable {
    let id: String
    let targets: [Target]
    let actions: [Action]
    let priority: Int
    let status: String
    let createdOn: String?
    let modifiedOn: String?

    struct Target: Codable, Sendable {
        let target: String
        let constraint: Constraint
        struct Constraint: Codable, Sendable {
            let operatorValue: String
            let value: String
            enum CodingKeys: String, CodingKey {
                case value
                case operatorValue = "operator"
            }
        }
    }

    struct Action: Codable, Sendable {
        let id: String
        let value: JSONValue?
    }

    enum CodingKeys: String, CodingKey {
        case id, targets, actions, priority, status
        case createdOn = "created_on"
        case modifiedOn = "modified_on"
    }
}
