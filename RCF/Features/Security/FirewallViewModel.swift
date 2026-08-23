import Foundation
import SwiftUI

/// Firewall hub: WAF custom rules, IP access rules, legacy rules.
@MainActor
@Observable
final class FirewallViewModel {
    enum Tab { case waf, ip, legacy }

    let zone: Zone
    let session: Session

    // WAF custom rules (rulesets)
    private(set) var rulesetId: String?
    private(set) var wafRules: [Ruleset.RulesetRule] = []
    // IP access rules
    private(set) var ipRules: [IPAccessRule] = []
    // Legacy firewall rules
    private(set) var legacyRules: [FirewallRule] = []

    private(set) var loadingTab: Tab?
    private(set) var busy = false
    private(set) var message: String?

    init(zone: Zone, session: Session) {
        self.zone = zone
        self.session = session
    }

    // MARK: - Loads

    func loadWAF() async {
        loadingTab = .waf
        defer { loadingTab = nil }
        do {
            let response: CloudflareResponse<Ruleset> = try await session.client.send(CloudflareEndpoint.wafCustomEntrypoint(zoneId: zone.id))
            rulesetId = response.result?.id
            wafRules = response.result?.rules ?? []
        } catch let error as CloudflareError where error.isPermissionDenied || Self.isNotFound(error) {
            // Virgin zone: no entrypoint yet.
            rulesetId = nil
            wafRules = []
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Failed to load custom rules"
        }
    }

    func loadIP() async {
        loadingTab = .ip
        defer { loadingTab = nil }
        do {
            let (list, _): ([IPAccessRule], ResultInfo?) = try await session.client.sendList(CloudflareEndpoint.ipAccessRules(zoneId: zone.id))
            ipRules = list
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Failed to load IP rules"
        }
    }

    func loadLegacy() async {
        loadingTab = .legacy
        defer { loadingTab = nil }
        do {
            let (list, _): ([FirewallRule], ResultInfo?) = try await session.client.sendList(CloudflareEndpoint.firewallRules(zoneId: zone.id))
            legacyRules = list
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Failed to load legacy rules"
        }
    }

    // MARK: - WAF mutations

    /// Ensures the entrypoint ruleset exists (create on 404-virgin zone), returns its id.
    private func ensureRuleset() async throws -> String {
        if let rulesetId { return rulesetId }
        let response: CloudflareResponse<Ruleset> = try await session.client.send(try CloudflareEndpoint.createWAFEntrypoint(zoneId: zone.id))
        guard let id = response.result?.id else { throw CloudflareError.emptyResult }
        rulesetId = id
        return id
    }

    func createWAFRule(action: String, expression: String, description: String?) async {
        await mutate {
            let rulesetId = try await self.ensureRuleset()
            let _: CloudflareResponse<Ruleset> = try await self.session.client.send(
                try CloudflareEndpoint.createRulesetRule(zoneId: self.zone.id, rulesetId: rulesetId, action: action, expression: expression, description: description, enabled: true)
            )
        }
        await loadWAF()
    }

    func updateWAFRule(_ rule: Ruleset.RulesetRule, enabled: Bool? = nil, action: String? = nil, expression: String? = nil, description: String? = nil) async {
        guard let rulesetId else { return }
        await mutate {
            let _: CloudflareResponse<Ruleset> = try await self.session.client.send(
                try CloudflareEndpoint.updateRulesetRule(zoneId: self.zone.id, rulesetId: rulesetId, ruleId: rule.id, action: action, expression: expression, description: description, enabled: enabled)
            )
        }
        await loadWAF()
    }

    func deleteWAFRule(_ rule: Ruleset.RulesetRule) async {
        guard let rulesetId else { return }
        await mutate {
            let _: CloudflareResponse<Ruleset> = try await self.session.client.send(
                CloudflareEndpoint.deleteRulesetRule(zoneId: self.zone.id, rulesetId: rulesetId, ruleId: rule.id)
            )
        }
        await loadWAF()
    }

    // MARK: - IP access mutations

    func createIPRule(mode: String, target: String, value: String, notes: String?) async {
        await mutate {
            let _: CloudflareResponse<IPAccessRule> = try await self.session.client.send(
                try CloudflareEndpoint.createIPAccessRule(zoneId: self.zone.id, mode: mode, targetKind: target, value: value, notes: notes)
            )
        }
        await loadIP()
    }

    func setIPRuleMode(_ rule: IPAccessRule, mode: String) async {
        await mutate {
            let _: CloudflareResponse<IPAccessRule> = try await self.session.client.send(
                try CloudflareEndpoint.updateIPAccessRule(zoneId: self.zone.id, ruleId: rule.id, mode: mode, notes: rule.notes)
            )
        }
        await loadIP()
    }

    func deleteIPRule(_ rule: IPAccessRule) async {
        await mutate {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(
                CloudflareEndpoint.deleteIPAccessRule(zoneId: self.zone.id, ruleId: rule.id)
            )
        }
        await loadIP()
    }

    // MARK: - Legacy mutations

    func toggleLegacyRule(_ rule: FirewallRule) async {
        await mutate {
            let _: CloudflareResponse<FirewallRule> = try await self.session.client.send(
                try CloudflareEndpoint.updateFirewallRule(zoneId: self.zone.id, ruleId: rule.id, paused: !rule.paused)
            )
        }
        await loadLegacy()
    }

    func deleteLegacyRule(_ rule: FirewallRule) async {
        await mutate {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(
                CloudflareEndpoint.deleteFirewallRule(zoneId: self.zone.id, ruleId: rule.id)
            )
        }
        await loadLegacy()
    }

    // MARK: - Helpers

    private func mutate(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await operation()
            Haptics.success()
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Operation failed"
            Haptics.error()
        }
    }

    static func isNotFound(_ error: CloudflareError) -> Bool {
        if case let .http(status, _) = error, status == 404 { return true }
        if case let .api(code, message, _) = error {
            // Cloudflare has returned different codes (10073, 10071, …) for the
            // same missing-entrypoint error; match the canonical message too.
            if code == 10073 { return true }
            return message.localizedCaseInsensitiveContains("could not find entrypoint ruleset")
        }
        return false
    }
}

/// Basic expression validation (balanced parens + quotes) for the editor.
nonisolated enum ExpressionValidator {
    static func isValid(_ expression: String) -> Bool {
        var parens = 0
        var inQuote = false
        var previous: Character?
        for character in expression {
            switch character {
            case "(":
                if !inQuote { parens += 1 }
            case ")":
                if !inQuote { parens -= 1; if parens < 0 { return false } }
            case "\"":
                if previous != "\\" { inQuote.toggle() }
            default:
                break
            }
            previous = character
        }
        return parens == 0 && !inQuote
    }
}
