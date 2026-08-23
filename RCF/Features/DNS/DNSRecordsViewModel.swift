import Foundation
import SwiftUI

/// DNS records list: filter, search, pagination, batch ops, CRUD, import/export.
@MainActor
@Observable
final class DNSRecordsViewModel {
    enum State { case loading, loaded, empty, error(String) }

    let zone: Zone
    let session: Session

    private(set) var state: State = .loading
    private(set) var records: [DNSRecord] = []
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var busyRecordIds: Set<String> = []
    private var page = 1
    private var searchTask: Task<Void, Never>?

    var searchText = "" {
        didSet { scheduleSearch() }
    }
    var typeFilter: String = "" {
        didSet { Task { await loadFirstPage() } }
    }
    /// Batch selection mode.
    var selection = Set<String>()

    init(zone: Zone, session: Session) {
        self.zone = zone
        self.session = session
    }

    func loadFirstPage() async {
        state = records.isEmpty ? .loading : .loaded
        page = 1
        hasMore = true
        await fetch(page: 1)
    }

    func loadMoreIfNeeded(current record: DNSRecord) async {
        guard hasMore, !isLoadingMore, record.id == records.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        page += 1
        await fetch(page: page)
    }

    func create(_ input: DNSRecordInput) async throws {
        let _: CloudflareResponse<DNSRecord> = try await session.client.send(
            CloudflareEndpoint.createDNSRecord(zoneId: zone.id, input: input)
        )
        await loadFirstPage()
    }

    func update(recordId: String, input: DNSRecordInput) async throws {
        let _: CloudflareResponse<DNSRecord> = try await session.client.send(
            CloudflareEndpoint.updateDNSRecord(zoneId: zone.id, recordId: recordId, input: input)
        )
        await loadFirstPage()
    }

    func delete(_ record: DNSRecord) async {
        guard !busyRecordIds.contains(record.id) else { return }
        busyRecordIds.insert(record.id)
        defer { busyRecordIds.remove(record.id) }
        do {
            let _: CloudflareResponse<NullResult> = try await session.client.send(
                CloudflareEndpoint.deleteDNSRecord(zoneId: zone.id, recordId: record.id)
            )
            records.removeAll { $0.id == record.id }
            selection.remove(record.id)
            if records.isEmpty { state = .empty }
            Haptics.success()
        } catch {
            Haptics.error()
        }
    }

    func setProxied(_ record: DNSRecord, proxied: Bool) async {
        let input = DNSRecordInput(
            type: record.type,
            name: record.name,
            content: record.content,
            ttl: record.ttl,
            proxied: proxied,
            priority: record.priority,
            comment: record.comment
        )
        busyRecordIds.insert(record.id)
        defer { busyRecordIds.remove(record.id) }
        do {
            let _: CloudflareResponse<DNSRecord> = try await session.client.send(
                CloudflareEndpoint.updateDNSRecord(zoneId: zone.id, recordId: record.id, input: input)
            )
            await loadFirstPage()
            Haptics.success()
        } catch {
            Haptics.error()
        }
    }

    // MARK: - Batch ops

    func batchDelete() async {
        let targets = records.filter { selection.contains($0.id) }
        for record in targets {
            await delete(record)
        }
        selection.removeAll()
    }

    func batchSetProxied(_ proxied: Bool) async {
        let targets = records.filter { selection.contains($0.id) && recordIsProxyEligible($0) }
        for record in targets {
            await setProxied(record, proxied: proxied)
        }
        selection.removeAll()
    }

    /// Orange-cloud eligibility (A/AAAA/CNAME only).
    func recordIsProxyEligible(_ record: DNSRecord) -> Bool {
        record.proxiable && (record.type == .a || record.type == .aaaa || record.type == .cname)
    }

    // MARK: - Import / export

    func exportBIND() async throws -> String {
        let (data, _) = try await session.client.sendRaw(CloudflareEndpoint.exportDNSZone(zoneId: zone.id))
        return String(decoding: data, as: UTF8.self)
    }

    func importBIND(fileData: Data, filename: String, proxied: Bool) async throws -> DNSImportResult {
        let response: CloudflareResponse<DNSImportResult> = try await session.client.send(
            CloudflareEndpoint.importDNSZone(zoneId: zone.id, fileData: fileData, filename: filename, proxied: proxied)
        )
        await loadFirstPage()
        return try response.result ?? { throw CloudflareError.emptyResult }()
    }

    // MARK: - Internals

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await loadFirstPage()
        }
    }

    private func fetch(page: Int) async {
        do {
            let (list, info): ([DNSRecord], ResultInfo?) = try await session.client.sendList(
                CloudflareEndpoint.dnsRecords(zoneId: zone.id, page: page, type: typeFilter.isEmpty ? nil : typeFilter, name: searchText.isEmpty ? nil : searchText)
            )
            if page == 1 {
                records = list
            } else {
                records.append(contentsOf: list)
            }
            hasMore = (info?.totalPages ?? 1) > page && !list.isEmpty
            state = records.isEmpty ? .empty : .loaded
        } catch {
            if page == 1 {
                state = .error((error as? CloudflareError)?.userMessage ?? "Failed to load records")
            }
        }
    }
}
