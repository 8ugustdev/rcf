import Foundation
import SwiftUI

/// Email routing: settings, enable/disable w/ DNS records, rules + catch-all, destinations.
@MainActor
@Observable
final class EmailRoutingViewModel {
    enum State { case loading, loaded, notConfigured, error(String) }

    let zone: Zone
    let session: Session

    private(set) var state: State = .loading
    private(set) var settings: EmailRoutingSettings?
    private(set) var dnsRecords: [EmailRoutingDnsRecord] = []
    private(set) var rules: [EmailRoutingRule] = []
    private(set) var catchAll: EmailRoutingRule?
    private(set) var destinations: [EmailDestination] = []
    private(set) var busy = false
    private(set) var message: String?

    init(zone: Zone, session: Session) {
        self.zone = zone
        self.session = session
    }

    func loadAll() async {
        state = .loading
        do {
            let response: CloudflareResponse<EmailRoutingSettings> = try await session.client.send(
                CloudflareEndpoint.emailRoutingSettings(zoneId: zone.id)
            )
            settings = response.result
            state = .loaded
            async let dns = loadDNS()
            async let ruleList = loadRules()
            async let dests = loadDestinations()
            _ = await (dns, ruleList, dests)
        } catch let error as CloudflareError where isNotFound(error) {
            state = .notConfigured
        } catch {
            state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load email routing")
        }
    }

    func enable() async {
        await mutate {
            let _: CloudflareResponse<EmailRoutingSettings> = try await self.session.client.send(
                CloudflareEndpoint.enableEmailRouting(zoneId: self.zone.id)
            )
        }
        await loadAll()
    }

    func disable() async {
        await mutate {
            let _: CloudflareResponse<EmailRoutingSettings> = try await self.session.client.send(
                CloudflareEndpoint.disableEmailRouting(zoneId: self.zone.id)
            )
        }
        await loadAll()
    }

    func saveRule(_ draft: EmailRoutingRule, isNew: Bool) async {
        await mutate {
            var rule = draft
            if isNew { rule.id = nil }
            if let id = rule.id {
                let _: CloudflareResponse<EmailRoutingRule> = try await self.session.client.send(
                    try CloudflareEndpoint.updateEmailRule(zoneId: self.zone.id, ruleId: id, rule: rule)
                )
            } else {
                let _: CloudflareResponse<EmailRoutingRule> = try await self.session.client.send(
                    try CloudflareEndpoint.createEmailRule(zoneId: self.zone.id, rule: rule)
                )
            }
        }
        await loadRules()
    }

    func deleteRule(_ rule: EmailRoutingRule) async {
        guard let id = rule.id else { return }
        await mutate {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(
                CloudflareEndpoint.deleteEmailRule(zoneId: self.zone.id, ruleId: id)
            )
        }
        await loadRules()
    }

    func toggleRule(_ rule: EmailRoutingRule) async {
        var updated = rule
        updated.enabled.toggle()
        await saveRule(updated, isNew: false)
    }

    func updateCatchAll(actionType: String, destinations: [String]) async {
        var rule = catchAll ?? EmailRoutingRule(
            id: nil, name: "catch-all", enabled: false, priority: 100,
            matchers: [.catchAll()], actions: [.drop()]
        )
        switch actionType {
        case "forward": rule.actions = [.forward(destinations)]
        case "worker": rule.actions = [destinations.first.map { .worker($0) } ?? .drop()]
        default: rule.actions = [.drop()]
        }
        await mutate {
            let _: CloudflareResponse<EmailRoutingRule> = try await self.session.client.send(
                try CloudflareEndpoint.updateCatchAllRule(zoneId: self.zone.id, rule: rule)
            )
        }
        await loadRules()
    }

    func toggleCatchAll() async {
        guard var rule = catchAll else { return }
        rule.enabled.toggle()
        await mutate {
            let _: CloudflareResponse<EmailRoutingRule> = try await self.session.client.send(
                try CloudflareEndpoint.updateCatchAllRule(zoneId: self.zone.id, rule: rule)
            )
        }
        await loadRules()
    }

    func addDestination(email: String) async {
        guard let accountId = session.accountId else { return }
        await mutate {
            let _: CloudflareResponse<EmailDestination> = try await self.session.client.send(
                try CloudflareEndpoint.addDestinationAddress(accountId: accountId, email: email)
            )
        }
        await loadDestinations()
    }

    func deleteDestination(_ destination: EmailDestination) async {
        guard let accountId = session.accountId, let id = destination.id else { return }
        await mutate {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(
                CloudflareEndpoint.deleteDestinationAddress(accountId: accountId, addressId: id)
            )
        }
        await loadDestinations()
    }

    var verifiedDestinations: [EmailDestination] {
        destinations.filter { $0.verified != nil }
    }

    // MARK: - Loads

    private func loadDNS() async {
        guard let response: CloudflareResponse<[EmailRoutingDnsRecord]> = try? await session.client.send(
            CloudflareEndpoint.emailRoutingDNS(zoneId: zone.id)
        ) else { return }
        dnsRecords = response.result ?? []
    }

    @discardableResult
    private func loadRules() async -> Bool {
        do {
            let (list, _): ([EmailRoutingRule], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.emailRules(zoneId: zone.id)
            )
            rules = list.filter { $0.name != "catch-all" }
            if let catchAllResponse: CloudflareResponse<EmailRoutingRule> = try? await session.client.send(
                CloudflareEndpoint.catchAllRule(zoneId: zone.id)
            ) {
                catchAll = catchAllResponse.result
            }
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private func loadDestinations() async -> Bool {
        guard let accountId = session.accountId else { return false }
        guard let (list, _): ([EmailDestination], ResultInfo?) = try? await session.client.sendList(
            CloudflareEndpoint.destinationAddresses(accountId: accountId)
        ) else { return false }
        destinations = list
        return true
    }

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

    private func isNotFound(_ error: CloudflareError) -> Bool {
        if case let .http(status, _) = error, status == 404 { return true }
        return false
    }
}
