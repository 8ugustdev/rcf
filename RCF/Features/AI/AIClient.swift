import Foundation

nonisolated enum AIClientError: LocalizedError {
    case notConfigured, invalidURL, invalidResponse, provider(String), emptyContent, invalidJSON(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: "Configure an AI provider first."
        case .invalidURL: "The provider URL is invalid."
        case .invalidResponse: "The provider returned an invalid response."
        case let .provider(message): message
        case .emptyContent: "The provider returned no content."
        case let .invalidJSON(raw): "Could not decode the response.\n\n\(raw)"
        }
    }
}

/// Minimal OpenAI-compatible chat-completions client.
nonisolated struct AIClient: Sendable {
    struct Message: Codable, Sendable { let role: String; let content: String }
    let provider: AIProvider
    let session: URLSession

    init(provider: AIProvider, session: URLSession = .shared) {
        self.provider = provider
        self.session = session
    }

    func chat(messages: [Message], jsonMode: Bool = false) async throws -> String {
        guard provider.isConfigured else { throw AIClientError.notConfigured }
        let root = provider.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: root + "/chat/completions") else { throw AIClientError.invalidURL }
        struct Body: Encodable {
            let model: String
            let messages: [Message]
            let responseFormat: [String: String]?
            enum CodingKeys: String, CodingKey { case model, messages; case responseFormat = "response_format" }
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(model: provider.model, messages: messages, responseFormat: jsonMode ? ["type": "json_object"] : nil))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = object?["error"] as? [String: Any]
            throw AIClientError.provider(error?["message"] as? String ?? String(data: data, encoding: .utf8) ?? "Provider error \(http.statusCode)")
        }
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let choices: [Choice]
        }
        guard let content = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content, !content.isEmpty else {
            throw AIClientError.emptyContent
        }
        return content
    }

    func json<T: Decodable & Sendable>(_ type: T.Type, messages: [Message]) async throws -> T {
        let raw = try await chat(messages: messages, jsonMode: true)
        guard let data = Self.extractJSON(from: raw), let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw AIClientError.invalidJSON(raw)
        }
        return value
    }

    /// Tolerant JSON extraction: plain JSON, fenced JSON, or prose wrapping first object/array.
    static func extractJSON(from raw: String) -> Data? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let data = text.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil { return data }
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let opener = text[start], closer: Character = opener == "{" ? "}" : "]"
        guard let end = text.lastIndex(of: closer), start <= end else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil else { return nil }
        return data
    }
}
