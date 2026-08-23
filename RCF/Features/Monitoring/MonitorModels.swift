import Foundation

/// Monitoring config (RN `monitoring.ts` DEFAULT_CONFIG parity).
nonisolated struct MonitorConfig: Codable, Sendable, Equatable {
    var enabled = false
    var zoneIds: [String] = []
    /// Alert when 5xx rate over the last hour exceeds this percentage.
    var errorRatePct = 20
    /// Alert when requests in the last hour are this many times the recent average.
    var spikeMultiplier = 3
    /// Alert this many days before a certificate expires.
    var sslDaysBefore = 14

    static let `default` = MonitorConfig()
}

/// Alert kinds + cooldown intervals (RN parity: down 1h, spike 3h, threats 6h, ssl 24h).
nonisolated struct MonitorAlert: Codable, Sendable, Identifiable, Equatable {
    enum Kind: String, Codable, Sendable {
        case down, spike, ssl, threats

        var cooldown: TimeInterval {
            switch self {
            case .down: 3600
            case .spike: 3 * 3600
            case .threats: 6 * 3600
            case .ssl: 24 * 3600
            }
        }

        var icon: String {
            switch self {
            case .down: "exclamationmark.triangle"
            case .spike: "chart.line.uptrend.xyaxis"
            case .ssl: "lock.rotation"
            case .threats: "shield.lefthalf.filled"
            }
        }
    }

    let id: String
    let kind: Kind
    let zoneName: String
    let title: String
    let body: String
    let at: Date
}

/// Per-zone dedupe state: last alert time per kind.
nonisolated struct MonitorZoneState: Codable, Sendable, Equatable {
    var lastAlertAt: [MonitorAlert.Kind: Date] = [:]

    enum CodingKeys: String, CodingKey { case lastAlertAt }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode([String: Date].self, forKey: .lastAlertAt)
        lastAlertAt = [:]
        for (key, value) in raw {
            if let kind = MonitorAlert.Kind(rawValue: key) {
                lastAlertAt[kind] = value
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: lastAlertAt.map { ($0.rawValue, $1) }), forKey: .lastAlertAt)
    }
}

typealias MonitorState = [String: MonitorZoneState]

/// Keychain-backed monitor persistence (config/state/history; zone names = PII → SecureStore parity).
nonisolated struct MonitorStore {
    let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore(service: "rcf.monitor")) {
        self.keychain = keychain
    }

    func loadConfig() -> MonitorConfig {
        guard let data = try? keychain.read(account: "config"),
              let config = try? JSONDecoder().decode(MonitorConfig.self, from: data) else {
            return .default
        }
        return config
    }

    func saveConfig(_ config: MonitorConfig) {
        if let data = try? JSONEncoder().encode(config) {
            try? keychain.write(data, account: "config")
        }
    }

    func loadState() -> MonitorState {
        guard let data = try? keychain.read(account: "state"),
              let state = try? JSONDecoder().decode(MonitorState.self, from: data) else {
            return [:]
        }
        return state
    }

    func saveState(_ state: MonitorState) {
        if let data = try? JSONEncoder().encode(state) {
            try? keychain.write(data, account: "state")
        }
    }

    /// History, newest first, capped at 50 (RN parity).
    func loadHistory() -> [MonitorAlert] {
        guard let data = try? keychain.read(account: "history"),
              let history = try? JSONDecoder().decode([MonitorAlert].self, from: data) else {
            return []
        }
        return history
    }

    func pushHistory(_ alerts: [MonitorAlert]) {
        guard !alerts.isEmpty else { return }
        var next = alerts + loadHistory()
        if next.count > 50 {
            next = Array(next.prefix(50))
        }
        if let data = try? JSONEncoder().encode(next) {
            try? keychain.write(data, account: "history")
        }
    }

    func clearHistory() {
        try? keychain.delete(account: "history")
    }
}
