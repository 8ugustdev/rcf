import Foundation

nonisolated enum AIBackend: String, CaseIterable, Sendable, Identifiable {
    case appleIntelligence
    case openAICompatible

    var id: String { rawValue }
    var title: String {
        switch self {
        case .appleIntelligence: "Apple Intelligence"
        case .openAICompatible: "OpenAI-compatible"
        }
    }
}

/// OpenAI-compatible provider settings. API key is Keychain-only.
nonisolated struct AIProvider: Sendable, Equatable {
    var baseURL: String
    var model: String
    var apiKey: String

    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"
    var isConfigured: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Persists non-secret preferences in UserDefaults and the key in Keychain.
nonisolated struct AIProviderStore {
    private let defaults: UserDefaults
    private let keychain: KeychainStore

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore(service: "rcf.ai")) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func loadBackend() -> AIBackend {
        guard let value = defaults.string(forKey: "rcf.ai.backend") else { return .appleIntelligence }
        return AIBackend(rawValue: value) ?? .appleIntelligence
    }

    func saveBackend(_ backend: AIBackend) {
        defaults.set(backend.rawValue, forKey: "rcf.ai.backend")
    }

    func load() -> AIProvider {
        let baseURL = defaults.string(forKey: "rcf.ai.baseURL") ?? AIProvider.defaultBaseURL
        let model = defaults.string(forKey: "rcf.ai.model") ?? AIProvider.defaultModel
        let key = (try? keychain.read(account: "apiKey")).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return AIProvider(baseURL: baseURL, model: model, apiKey: key)
    }

    func save(_ provider: AIProvider) {
        defaults.set(provider.baseURL, forKey: "rcf.ai.baseURL")
        defaults.set(provider.model, forKey: "rcf.ai.model")
        if provider.apiKey.isEmpty {
            try? keychain.delete(account: "apiKey")
        } else {
            try? keychain.write(Data(provider.apiKey.utf8), account: "apiKey")
        }
    }
}

nonisolated struct AuditResult: Codable, Sendable {
    struct Finding: Codable, Sendable, Identifiable {
        enum Severity: String, Codable, Sendable { case critical, high, medium, low, info }
        var id: String { "\(severity.rawValue)-\(title)" }
        let severity: Severity
        let title: String
        let detail: String
        let action: String
    }
    let score: Int
    let summary: String
    let findings: [Finding]
}

nonisolated struct TrafficInsight: Codable, Sendable {
    let summary: String
    let observations: [String]
    let recommendations: [String]
}

nonisolated struct SuggestedDNSRecord: Codable, Sendable, Identifiable {
    var id: String { "\(type)-\(name)-\(content)" }
    let type: String
    let name: String
    let content: String
    let ttl: Int?
    let proxied: Bool?
    let reason: String?
}
