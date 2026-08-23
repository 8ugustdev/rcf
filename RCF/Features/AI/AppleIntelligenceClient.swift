import Foundation
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
private struct AppleTrafficInsight {
    var summary: String
    var observations: [String]
    var recommendations: [String]
}

@available(iOS 26.0, *)
@Generable
private struct AppleAuditFinding {
    var severity: String
    var title: String
    var detail: String
    var action: String
}

@available(iOS 26.0, *)
@Generable
private struct AppleAuditResult {
    var score: Int
    var summary: String
    var findings: [AppleAuditFinding]
}

@available(iOS 26.0, *)
@Generable
private struct AppleDNSRecord {
    var type: String
    var name: String
    var content: String
    var ttl: Int
    var proxied: Bool
    var reason: String
}

@available(iOS 26.0, *)
@Generable
private struct AppleDNSRecords {
    var records: [AppleDNSRecord]
}
#endif

nonisolated enum AppleIntelligenceError: LocalizedError {
    case requiresIOS26
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .requiresIOS26:
            "Apple Intelligence requires iOS 26 or later."
        case let .unavailable(reason):
            reason
        }
    }
}

/// On-device Apple Foundation Models client. No prompt or zone data leaves the device.
nonisolated struct AppleIntelligenceClient: Sendable {
    var availabilityMessage: String? {
        guard #available(iOS 26.0, *) else {
            return "Apple Intelligence requires iOS 26 or later."
        }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "Apple Intelligence is not supported on this device."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Enable Apple Intelligence in the Settings app."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading or preparing its model."
        @unknown default:
            return "Apple Intelligence is currently unavailable."
        }
        #else
        return "Apple Intelligence is unavailable in this build."
        #endif
    }

    var isAvailable: Bool { availabilityMessage == nil }

    func chat(messages: [AIClient.Message], jsonMode: Bool = false) async throws -> String {
        guard #available(iOS 26.0, *) else { throw AppleIntelligenceError.requiresIOS26 }
        #if canImport(FoundationModels)
        let (session, prompt) = try sessionAndPrompt(messages: messages)
        let suffix = jsonMode ? "\n\nReturn only the requested structured result." : ""
        let response = try await session.respond(to: prompt + suffix)
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw AIClientError.emptyContent }
        return content
        #else
        throw AppleIntelligenceError.unavailable("Apple Intelligence is unavailable in this build.")
        #endif
    }

    func json<T: Decodable & Sendable>(_ type: T.Type, messages: [AIClient.Message]) async throws -> T {
        guard #available(iOS 26.0, *) else { throw AppleIntelligenceError.requiresIOS26 }
        #if canImport(FoundationModels)
        let (session, prompt) = try sessionAndPrompt(messages: messages)
        if type == TrafficInsight.self {
            let value = try await session.respond(to: prompt, generating: AppleTrafficInsight.self).content
            return TrafficInsight(summary: value.summary, observations: value.observations, recommendations: value.recommendations) as! T
        }
        if type == AuditResult.self {
            let value = try await session.respond(to: prompt, generating: AppleAuditResult.self).content
            let findings = value.findings.map {
                AuditResult.Finding(
                    severity: AuditResult.Finding.Severity(rawValue: $0.severity.lowercased()) ?? .info,
                    title: $0.title,
                    detail: $0.detail,
                    action: $0.action
                )
            }
            return AuditResult(score: min(100, max(0, value.score)), summary: value.summary, findings: findings) as! T
        }
        if type == [SuggestedDNSRecord].self {
            let value = try await session.respond(to: prompt, generating: AppleDNSRecords.self).content
            let records = value.records.map {
                SuggestedDNSRecord(type: $0.type, name: $0.name, content: $0.content, ttl: $0.ttl, proxied: $0.proxied, reason: $0.reason)
            }
            return records as! T
        }
        let raw = try await chat(messages: messages, jsonMode: true)
        guard let data = AIClient.extractJSON(from: raw), let value = try? JSONDecoder().decode(T.self, from: data) else {
            throw AIClientError.invalidJSON(raw)
        }
        return value
        #else
        throw AppleIntelligenceError.unavailable("Apple Intelligence is unavailable in this build.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func sessionAndPrompt(messages: [AIClient.Message]) throws -> (LanguageModelSession, String) {
        if let availabilityMessage { throw AppleIntelligenceError.unavailable(availabilityMessage) }
        let instructions = messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
        let prompt = messages.filter { $0.role != "system" }.map(\.content).joined(separator: "\n\n")
        return (LanguageModelSession(instructions: instructions.isEmpty ? nil : instructions), prompt)
    }
    #endif
}
