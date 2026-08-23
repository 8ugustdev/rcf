import Foundation

/// Routes AI requests through the explicitly selected backend.
/// Apple mode never silently falls back to a network provider.
nonisolated struct AIService: Sendable {
    let backend: AIBackend
    let provider: AIProvider

    init(backend: AIBackend? = nil, provider: AIProvider? = nil, store: AIProviderStore = AIProviderStore()) {
        self.backend = backend ?? store.loadBackend()
        self.provider = provider ?? store.load()
    }

    var availabilityMessage: String? {
        switch backend {
        case .appleIntelligence:
            AppleIntelligenceClient().availabilityMessage
        case .openAICompatible:
            provider.isConfigured ? nil : "Add an OpenAI-compatible API key in Settings."
        }
    }

    var isAvailable: Bool { availabilityMessage == nil }

    func chat(messages: [AIClient.Message]) async throws -> String {
        switch backend {
        case .appleIntelligence:
            return try await AppleIntelligenceClient().chat(messages: messages)
        case .openAICompatible:
            return try await AIClient(provider: provider).chat(messages: messages)
        }
    }

    func json<T: Decodable & Sendable>(_ type: T.Type, messages: [AIClient.Message]) async throws -> T {
        switch backend {
        case .appleIntelligence:
            return try await AppleIntelligenceClient().json(type, messages: messages)
        case .openAICompatible:
            return try await AIClient(provider: provider).json(type, messages: messages)
        }
    }
}
