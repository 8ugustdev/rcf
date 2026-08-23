import Foundation

/// Pure monitoring logic (RN `runChecks` parity, unit-testable, no UIKit).
nonisolated enum MonitorEngine {
    /// One hour bucket from GraphQL httpRequests1hGroups.
    struct HourlyPoint: Sendable, Equatable {
        let requests: Int
        let errors: Int
        let threats: Int
    }

    /// Inputs for one zone in a cycle.
    struct ZoneInput: Sendable {
        let zoneId: String
        let zoneName: String
        let hourly: [HourlyPoint]
        let sslDaysLeft: Int?
    }

    /// Runs the check cycle; returns deduped alerts and the updated state.
    /// - Parameters:
    ///   - inputs: per-zone snapshots (caller fetched analytics + ssl).
    ///   - config: thresholds.
    ///   - state: prior dedupe state.
    ///   - now: cycle timestamp.
    static func run(inputs: [ZoneInput], config: MonitorConfig, state: inout MonitorState, now: Date = .now) -> [MonitorAlert] {
        guard config.enabled else { return [] }
        var alerts: [MonitorAlert] = []
        let nowMs = now.timeIntervalSince1970 * 1000

        for input in inputs {
            guard config.zoneIds.contains(input.zoneId) else { continue }
            guard input.hourly.count >= 2 else { continue }

            let last = input.hourly[input.hourly.count - 1]
            let earlier = input.hourly.dropLast()
            let avgRequests = Double(earlier.reduce(0) { $0 + $1.requests }) / Double(max(earlier.count, 1))

            func cooledDown(_ kind: MonitorAlert.Kind) -> Bool {
                guard let last = state[input.zoneId]?.lastAlertAt[kind] else { return true }
                return now.timeIntervalSince(last) >= kind.cooldown
            }

            func mark(_ kind: MonitorAlert.Kind) {
                state[input.zoneId, default: MonitorZoneState()].lastAlertAt[kind] = now
            }

            func make(_ kind: MonitorAlert.Kind, title: String, body: String) -> MonitorAlert {
                MonitorAlert(id: "\(input.zoneId)-\(kind.rawValue)-\(Int(nowMs))", kind: kind, zoneName: input.zoneName, title: title, body: body, at: now)
            }

            // 1. Site trouble — high 5xx share.
            let errorPct = last.requests > 0 ? Double(last.errors) / Double(last.requests) * 100 : 0
            if errorPct >= Double(config.errorRatePct), last.requests >= 20, cooledDown(.down) {
                alerts.append(make(.down,
                    title: "⚠️ \(input.zoneName) is returning errors",
                    body: String(format: "%.0f%% of requests failed with 5xx in the last hour (%d of %d).", errorPct, last.errors, last.requests)))
                mark(.down)
            }

            // 2. Traffic spike.
            if avgRequests >= 50, Double(last.requests) >= avgRequests * Double(config.spikeMultiplier), cooledDown(.spike) {
                alerts.append(make(.spike,
                    title: "📈 Traffic spike on \(input.zoneName)",
                    body: String(format: "%@ requests in the last hour — %.1f× the recent average.", Formatters.compact(last.requests), Double(last.requests) / max(avgRequests, 1))))
                mark(.spike)
            }

            // 3. Threat surge.
            if last.threats >= 100, cooledDown(.threats) {
                alerts.append(make(.threats,
                    title: "🛡️ \(input.zoneName) under heavy attack",
                    body: "\(Formatters.compact(last.threats)) threats blocked in the last hour. Consider Under Attack Mode."))
                mark(.threats)
            }

            // 4. Certificate expiry.
            if let daysLeft = input.sslDaysLeft, daysLeft >= 0, daysLeft <= config.sslDaysBefore, cooledDown(.ssl) {
                alerts.append(make(.ssl,
                    title: "🔒 SSL expires in \(daysLeft) day\(daysLeft == 1 ? "" : "s")",
                    body: "The certificate for \(input.zoneName) expires soon. Renew it before visitors see warnings."))
                mark(.ssl)
            }
        }
        return alerts
    }

    // MARK: - Data fetching (runs outside the engine; pure decode helpers)

    /// Hourly GraphQL query (RN `fetchHourly` verbatim shape).
    static func hourlyQuery(zoneId: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let end = Date.now
        let start = end.addingTimeInterval(-24 * 3600)
        return """
        { viewer { zones(filter: { zoneTag: "\(zoneId)" }) {
          httpRequests1hGroups(limit: 24, filter: { datetime_geq: "\(formatter.string(from: start))", datetime_leq: "\(formatter.string(from: end))" }, orderBy: [datetime_ASC]) {
            dimensions { datetime }
            sum { requests threats responseStatusMap { edgeResponseStatus requests } }
          }
        } } }
        """
    }

    /// GraphQL response → hourly points.
    struct HourlyResponse: Decodable {
        let viewer: Viewer
        struct Viewer: Decodable {
            let zones: [ZoneNode]
        }
        struct ZoneNode: Decodable {
            let httpRequests1hGroups: [Group]?
        }
        struct Group: Decodable {
            let sum: Sum
        }
        struct Sum: Decodable {
            let requests: Int?
            let threats: Int?
            let responseStatusMap: [StatusEntry]?
        }
        struct StatusEntry: Decodable {
            let edgeResponseStatus: Int
            let requests: Int
        }
    }

    static func hourlyPoints(from response: HourlyResponse) -> [HourlyPoint] {
        let groups = response.viewer.zones.first?.httpRequests1hGroups ?? []
        return groups.map { group in
            let statuses = group.sum.responseStatusMap ?? []
            let errors = statuses
                .filter { $0.edgeResponseStatus >= 500 }
                .reduce(0) { $0 + $1.requests }
            return HourlyPoint(requests: group.sum.requests ?? 0, errors: errors, threats: group.sum.threats ?? 0)
        }
    }

    /// Certificate packs → days until soonest expiry (RN `fetchCertDaysLeft`).
    static func sslDaysLeft(certificatePacks: [CertificatePack], now: Date = .now) -> Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dates = certificatePacks
            .compactMap { $0.validity?.expiresOn }
            .compactMap { formatter.date(from: $0) }
        guard let soonest = dates.min() else { return nil }
        let days = Int((soonest.timeIntervalSince(now) / 86400).rounded(.down))
        return days
    }
}
