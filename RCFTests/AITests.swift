import XCTest
@testable import RCF

final class AITests: XCTestCase {
    func testExtractPlainJSON() throws {
        let data = try XCTUnwrap(AIClient.extractJSON(from: "{\"score\":90}"))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: data) as? [String: Int])?["score"], 90)
    }

    func testExtractFencedJSON() throws {
        let data = try XCTUnwrap(AIClient.extractJSON(from: "```json\n{\"ok\":true}\n```"))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: data) as? [String: Bool])
    }

    func testExtractWrappedJSON() {
        XCTAssertNotNil(AIClient.extractJSON(from: "Here it is: {\"ok\":true} thanks"))
    }

    func testMalformedJSONReturnsNil() {
        XCTAssertNil(AIClient.extractJSON(from: "```json\n{broken}\n```"))
        XCTAssertNil(AIClient.extractJSON(from: "nothing structured"))
    }

    func testAuditResultFixture() throws {
        let fixture = """
        {"score":82,"summary":"Solid","findings":[{"severity":"medium","title":"Cache","detail":"Low hit rate","action":"Review rules"}]}
        """
        let result = try JSONDecoder().decode(AuditResult.self, from: Data(fixture.utf8))
        XCTAssertEqual(result.score, 82)
        XCTAssertEqual(result.findings.first?.severity, .medium)
    }

    func testAuditPromptContainsSnapshotWithoutSecrets() {
        let messages = AIPrompts.audit(zoneName: "example.com", settings: ["ssl": .string("full")], records: [], sslPacks: [], firewallCount: 2)
        let text = messages.map(\.content).joined()
        XCTAssertTrue(text.contains("example.com"))
        XCTAssertTrue(text.contains("ssl"))
        XCTAssertTrue(text.contains("firewall_rule_count"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(text.contains("Bearer"))
    }

    func testAppleIntelligenceIsDefaultBackend() {
        let suite = "ai.backend.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = AIProviderStore(defaults: defaults, keychain: KeychainStore(service: suite))
        XCTAssertEqual(store.loadBackend(), .appleIntelligence)
        defaults.removePersistentDomain(forName: suite)
    }

    func testBackendSelectionPersists() {
        let suite = "ai.backend.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = AIProviderStore(defaults: defaults, keychain: KeychainStore(service: suite))
        store.saveBackend(.openAICompatible)
        XCTAssertEqual(store.loadBackend(), .openAICompatible)
        defaults.removePersistentDomain(forName: suite)
    }

    func testHostedServiceRequiresAPIKey() {
        let provider = AIProvider(baseURL: AIProvider.defaultBaseURL, model: AIProvider.defaultModel, apiKey: "")
        XCTAssertNotNil(AIService(backend: .openAICompatible, provider: provider).availabilityMessage)
    }

    func testProviderSecretStoredOnlyInKeychain() {
        let suite = "ai.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let keychain = KeychainStore(service: suite)
        let store = AIProviderStore(defaults: defaults, keychain: keychain)
        store.save(AIProvider(baseURL: "https://example.test/v1", model: "m", apiKey: "secret-key"))
        XCTAssertNil(defaults.string(forKey: "rcf.ai.apiKey"))
        XCTAssertEqual(store.load().apiKey, "secret-key")
        try? keychain.delete(account: "apiKey")
        defaults.removePersistentDomain(forName: suite)
    }
}
