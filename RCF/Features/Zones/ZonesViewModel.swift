import Foundation
import SwiftUI

/// Zones tab: searchable, paginated zone list with create/delete.
@MainActor
@Observable
final class ZonesViewModel {
    enum State { case loading, loaded, empty, error(String) }

    private(set) var state: State = .loading
    private(set) var zones: [Zone] = []
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private var page = 1
    private var searchTask: Task<Void, Never>?

    var searchText = "" {
        didSet { scheduleSearchRefresh() }
    }

    let session: Session

    init(session: Session) {
        self.session = session
    }

    func loadFirstPage() async {
        state = zones.isEmpty ? .loading : .loaded
        page = 1
        hasMore = true
        await fetch(page: 1)
    }

    func loadMoreIfNeeded(current zone: Zone) async {
        guard hasMore, !isLoadingMore, zone.id == zones.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        await fetch(page: page)
    }

    func refresh() async {
        await loadFirstPage()
    }

    func createZone(name: String) async throws {
        guard let accountId = session.accountId ?? session.accounts.first?.id else {
            throw CloudflareError.emptyResult
        }
        let _: CloudflareResponse<Zone> = try await session.client.send(CloudflareEndpoint.createZone(name: name, accountId: accountId))
        await loadFirstPage()
    }

    func deleteZone(_ zone: Zone) async throws {
        let _: CloudflareResponse<NullResult> = try await session.client.send(CloudflareEndpoint.deleteZone(id: zone.id))
        zones.removeAll { $0.id == zone.id }
        if zones.isEmpty { state = .empty }
    }

    private func scheduleSearchRefresh() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350)) // debounce
            guard !Task.isCancelled else { return }
            await loadFirstPage()
        }
    }

    private func fetch(page: Int) async {
        do {
            let (list, info): ([Zone], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.zones(page: page, search: searchText.isEmpty ? nil : searchText)
            )
            if page == 1 {
                zones = list
            } else {
                zones.append(contentsOf: list)
            }
            hasMore = (info?.totalPages ?? 1) > page && !list.isEmpty
            state = zones.isEmpty ? .empty : .loaded
        } catch {
            if page == 1 {
                state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load zones")
            }
        }
    }
}

/// Zone detail hub data: zone, settings toggles, DNSSEC, Argo.
@MainActor
@Observable
final class ZoneDetailViewModel {
    enum State { case loading, loaded, error(String) }

    let zoneId: String
    let session: Session

    private(set) var state: State = .loading
    private(set) var zone: Zone?
    private(set) var settings: [String: JSONValue] = [:]
    private(set) var dnssec: DNSSECStatus?
    private(set) var argoEnabled: Bool?
    private(set) var argoIsPaidFeature = false
    private(set) var busy = false
    private(set) var message: String?

    init(zoneId: String, session: Session, initialZone: Zone? = nil) {
        self.zoneId = zoneId
        self.session = session
        self.zone = initialZone
    }

    func load() async {
        state = zone == nil ? .loading : .loaded

        // The zones list already supplies the complete Zone DTO. Requiring a redundant
        // GET /zones/{id} made detail navigation fail for some Global API Key accounts
        // even though GET /zones succeeded. Only fetch when opened without list context.
        if zone == nil {
            do {
                let zoneResponse: CloudflareResponse<Zone> = try await session.client.send(CloudflareEndpoint.zone(id: zoneId))
                guard let fetched = zoneResponse.result else { throw CloudflareError.emptyResult }
                zone = fetched
                state = .loaded
            } catch {
                state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load zone")
                return
            }
        }

        // Optional capabilities must not prevent the detail hub from opening.
        if let (list, _): ([ZoneSettingValue], ResultInfo?) = try? await session.client.sendList(
            CloudflareEndpoint.zoneSettings(zoneId: zoneId)
        ) {
            settings = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.value) })
        }
        if let response: CloudflareResponse<DNSSECStatus> = try? await session.client.send(
            CloudflareEndpoint.dnssec(zoneId: zoneId)
        ) {
            dnssec = response.result
        }
        do {
            let argo: CloudflareResponse<ZoneSettingValue> = try await session.client.send(
                CloudflareEndpoint.argoSmartRouting(zoneId: zoneId)
            )
            argoEnabled = argo.result?.value == .bool(true)
        } catch let error as CloudflareError where error.isPermissionDenied {
            argoIsPaidFeature = true // free plan / no permission — graceful paid message
        } catch {
            // Argo is optional and must not replace otherwise usable zone content.
        }
    }

    // MARK: - Mutations (each re-reads state after write — plan requires live verification)

    func setDevelopmentMode(_ on: Bool) async {
        await patchSetting("development_mode", value: .bool(on))
    }

    func setUnderAttack(_ on: Bool) async {
        await patchSetting("security_level", value: .string(on ? "under_attack" : "medium"))
    }

    func setSetting(_ id: String, value: JSONValue) async {
        await patchSetting(id, value: value)
    }

    private func patchSetting(_ id: String, value: JSONValue) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let _: CloudflareResponse<ZoneSettingValue> = try await session.client.send(
                CloudflareEndpoint.updateZoneSetting(zoneId: zoneId, id: id, value: value)
            )
            settings[id] = value // optimistic
            await load() // re-fetch verify (plan gate)
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Update failed"
        }
    }

    func purgeEverything() async {
        await runMutation {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(CloudflareEndpoint.purgeEverything(zoneId: self.zoneId))
        } success: {
            "Cache purged"
        }
    }

    func purgeURLs(_ urls: [String]) async {
        await runMutation {
            let _: CloudflareResponse<NullResult> = try await self.session.client.send(CloudflareEndpoint.purgeURLs(zoneId: self.zoneId, urls: urls))
        } success: {
            "Purged \(urls.count) URL(s)"
        }
    }

    func setDnssec(_ enabled: Bool) async {
        await runMutation {
            let _: CloudflareResponse<DNSSECStatus> = try await self.session.client.send(
                CloudflareEndpoint.updateDnssec(zoneId: self.zoneId, status: enabled ? "active" : "disabled")
            )
        } success: {
            enabled ? "DNSSEC activation started" : "DNSSEC disabled"
        }
        if dnssec == nil || message?.contains("failed") != true {
            if let response: CloudflareResponse<DNSSECStatus> = try? await session.client.send(CloudflareEndpoint.dnssec(zoneId: zoneId)) {
                dnssec = response.result
            }
        }
    }

    func setArgo(_ on: Bool) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let _: CloudflareResponse<ZoneSettingValue> = try await session.client.send(
                CloudflareEndpoint.updateArgoSmartRouting(zoneId: zoneId, value: on)
            )
            argoEnabled = on
            message = on ? "Smart Routing enabled" : "Smart Routing disabled"
            Haptics.success()
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Argo update failed"
        }
    }

    private func runMutation(_ mutation: () async throws -> Void, success: () -> String) async {
        guard !busy else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await mutation()
            message = success()
            Haptics.success()
        } catch {
            message = (error as? CloudflareError)?.userMessage ?? "Operation failed"
        }
    }
}
