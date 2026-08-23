import Foundation

/// Auth material for one Cloudflare login. Whitespace is stripped from secrets
/// at construction time (RN parity: `replace(/\s+/g, '')`).
nonisolated enum AuthConfig: Codable, Sendable, Equatable {
    case token(String)
    case globalKey(email: String, key: String)

    private enum CodingKeys: String, CodingKey { case method, apiToken, email, globalKey }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let method = try container.decode(String.self, forKey: .method)
        switch method {
        case "token":
            self = .token(try container.decode(String.self, forKey: .apiToken))
        case "global_key":
            self = .globalKey(
                email: try container.decode(String.self, forKey: .email),
                key: try container.decode(String.self, forKey: .globalKey)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .method, in: container, debugDescription: "Unknown auth method \(method)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .token(apiToken):
            try container.encode("token", forKey: .method)
            try container.encode(apiToken, forKey: .apiToken)
        case let .globalKey(email, key):
            try container.encode("global_key", forKey: .method)
            try container.encode(email, forKey: .email)
            try container.encode(key, forKey: .globalKey)
        }
    }

    /// Builds the header set attached to every request (incl. GraphQL and raw).
    var headers: [(String, String)] {
        switch self {
        case let .token(apiToken):
            [("Authorization", "Bearer \(apiToken.filter { !$0.isWhitespace })")]
        case let .globalKey(email, key):
            [
                ("X-Auth-Email", email.filter { !$0.isWhitespace }),
                ("X-Auth-Key", key.filter { !$0.isWhitespace }),
            ]
        }
    }

    /// Masked description for UI display (never exposes the secret).
    var maskedDescription: String {
        switch self {
        case let .token(apiToken):
            "Token \(Masking.token(apiToken.filter { !$0.isWhitespace }))"
        case let .globalKey(email, _):
            "Global key (\(Masking.email(email)))"
        }
    }
}

/// A named Cloudflare login (multi-account support).
nonisolated struct Profile: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var label: String
    var auth: AuthConfig
    /// Account id resolved after first verify (used for account-scoped calls).
    var accountId: String?
    var createdAt: Date

    init(id: String = UUID().uuidString, label: String, auth: AuthConfig, accountId: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.label = label
        self.auth = auth
        self.accountId = accountId
        self.createdAt = createdAt
    }

    /// Default label before the real account name is known (RN `labelFor` parity).
    static func defaultLabel(for auth: AuthConfig) -> String {
        switch auth {
        case let .globalKey(email, _): email
        case let .token(apiToken): "Token ••••\(String(apiToken.filter { !$0.isWhitespace }.suffix(4)))"
        }
    }
}
