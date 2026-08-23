import Foundation

/// Strict-schema prompts. Snapshots intentionally contain no credentials.
nonisolated enum AIPrompts {
    static func audit(zoneName: String, settings: [String: JSONValue], records: [DNSRecord], sslPacks: [CertificatePack], firewallCount: Int) -> [AIClient.Message] {
        let snapshot: [String: Any] = [
            "zone": zoneName,
            "settings": settings.mapValues(\.displayString),
            "dns_records": records.prefix(200).map { ["type": $0.type, "name": $0.name, "content": $0.content, "proxied": $0.proxied as Any] },
            "ssl_pack_statuses": sslPacks.map(\.status),
            "firewall_rule_count": firewallCount,
        ]
        let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return [
            .init(role: "system", content: "You are a Cloudflare security and performance auditor. Never invent facts. Return strict JSON only."),
            .init(role: "user", content: "Audit this zone snapshot: \(json)\nReturn {\"score\":0-100,\"summary\":\"...\",\"findings\":[{\"severity\":\"critical|high|medium|low|info\",\"title\":\"...\",\"detail\":\"...\",\"action\":\"...\"}]}")
        ]
    }

    static func traffic(zoneName: String, analytics: GraphQLAnalytics) -> [AIClient.Message] {
        let summary = "zone=\(zoneName), requests=\(analytics.requestsTotal), cached=\(analytics.requestsCached), bytes=\(analytics.bytesTotal), threats=\(analytics.threatsTotal), pageviews=\(analytics.pageviewsTotal), uniques=\(analytics.uniquesTotal), datapoints=\(analytics.timeseries.count)"
        return [.init(role: "system", content: "Analyze Cloudflare traffic. Return strict JSON only."), .init(role: "user", content: "\(summary)\nReturn {\"summary\":\"...\",\"observations\":[\"...\"],\"recommendations\":[\"...\"]}")]
    }

    static func explain(logDescription: String) -> [AIClient.Message] {
        [.init(role: "system", content: "Explain Cloudflare activity accurately in plain English, including likely impact and safe next steps."), .init(role: "user", content: logDescription)]
    }

    static func dns(domain: String, purpose: String) -> [AIClient.Message] {
        [.init(role: "system", content: "You are a DNS expert. Return strict JSON only. Use @ for the apex. Do not invent destination values absent from the request."), .init(role: "user", content: "Domain: \(domain)\nPurpose: \(purpose)\nReturn a JSON array of {\"type\":\"A|AAAA|CNAME|MX|TXT|CAA|SRV\",\"name\":\"...\",\"content\":\"...\",\"ttl\":1,\"proxied\":false,\"reason\":\"...\"}.")]
    }
}
