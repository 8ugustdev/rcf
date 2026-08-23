import SwiftUI

/// One searchable/executable palette row.
nonisolated struct PaletteItem: Identifiable, Sendable {
    enum Kind: Sendable { case command, zone, record, worker }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String?
    let icon: String
    var destructive: Bool = false
    let run: @MainActor @Sendable () -> Void
}

/// Fuzzy matcher + sectioning for the command palette. Pure functions.
nonisolated enum PaletteEngine {
    /// Subsequence fuzzy score; nil = no match. Higher = better.
    /// Consecutive + word-start bonuses so "exm" ranks example.com above ex-mirror.io.
    static func score(query: String, title: String) -> Int? {
        let q = query.lowercased()
        guard !q.isEmpty else { return 0 }
        let t = title.lowercased()
        guard let first = q.first.flatMap({ t.firstIndex(of: $0) }) else { return nil }

        var score = 0
        var searchStart = t.startIndex
        var previousMatch: String.Index? = nil
        for ch in q {
            guard let found = t[searchStart...].firstIndex(of: ch) else { return nil }
            if found == t.index(after: searchStart) || searchStart == t.startIndex, previousMatch != nil {
                score += 4 // consecutive
            }
            if found == t.startIndex || t[t.index(before: found)] == "." || t[t.index(before: found)] == "/" || t[t.index(before: found)] == " " {
                score += 6 // word start
            }
            score += 1
            previousMatch = found
            searchStart = t.index(after: found)
        }
        // Prefer shorter titles (exact-ish matches rise).
        score -= t.count / 8
        return score
    }

    struct Section: Identifiable {
        let id: String
        let title: String
        let items: [PaletteItem]
    }

    /// Filters + orders items into sections. Commands always first.
    static func sections(query: String, commands: [PaletteItem], zones: [PaletteItem], records: [PaletteItem], workers: [PaletteItem]) -> [Section] {
        func ranked(_ items: [PaletteItem]) -> [PaletteItem] {
            guard !query.isEmpty else { return items }
            return items
                .compactMap { item -> (PaletteItem, Int)? in
                    guard let s = score(query: query, title: item.title) else { return nil }
                    return (item, s)
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        var result: [Section] = []
        if !ranked(commands).isEmpty { result.append(Section(id: "commands", title: "Commands", items: ranked(commands))) }
        if !ranked(zones).isEmpty { result.append(Section(id: "zones", title: "Zones", items: ranked(zones))) }
        if !ranked(records).isEmpty { result.append(Section(id: "records", title: "DNS Records", items: ranked(records))) }
        if !ranked(workers).isEmpty { result.append(Section(id: "workers", title: "Workers", items: ranked(workers))) }
        return result
    }
}

/// Data sources for the palette. Fetches once per open (never per keystroke):
/// account worker scripts + active-zone DNS records; zones come from ZoneCache.
@MainActor
@Observable
final class PaletteData {
    private(set) var records: [DNSRecord] = []
    private(set) var workers: [WorkerScript] = []

    let session: Session
    let activeZone: Zone?

    init(session: Session, activeZone: Zone?) {
        self.session = session
        self.activeZone = activeZone
    }

    func load() async {
        if let zoneId = activeZone?.id {
            do {
                let (list, _): ([DNSRecord], ResultInfo?) = try await session.client.sendList(
                    CloudflareEndpoint.dnsRecords(zoneId: zoneId, page: 1)
                )
                records = Array(list.prefix(100))
            } catch {
                records = []
            }
        }
        if let accountId = session.accountId {
            do {
                let (list, _): ([WorkerScript], ResultInfo?) = try await session.client.sendList(
                    CloudflareEndpoint.workerScripts(accountId: accountId)
                )
                workers = Array(list.prefix(100))
            } catch {
                workers = []
            }
        }
    }
}
