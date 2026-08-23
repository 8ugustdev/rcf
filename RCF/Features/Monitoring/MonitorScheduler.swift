import BackgroundTasks
import Foundation
import UserNotifications
import SwiftUI

/// Runs monitoring cycles: data fetch → engine → notifications; BG + foreground scheduling.
@MainActor
@Observable
final class MonitorScheduler {
    static let taskIdentifier = "rcf.monitor.refresh"
    /// Minimum interval between foreground checks (15 min, matching RN minimumInterval).
    static let minInterval: TimeInterval = 15 * 60

    let store: MonitorStore
    private(set) var lastRun: Date?
    private(set) var isRunning = false

    init(store: MonitorStore = MonitorStore()) {
        self.store = store
    }

    /// Registers the BG task handler — call once at app start.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                let scheduler = MonitorScheduler()
                await scheduler.runCycle(clientProvider: CurrentSessionClient.shared)
                refresh.setTaskCompleted(success: true)
                scheduler.scheduleBackgroundRefresh()
            }
        }
    }

    /// Submits the next BG refresh (earliest 15 min from now).
    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date.now.addingTimeInterval(Self.minInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Foreground trigger — respects min interval between runs.
    func foregroundRefreshIfNeeded(clientProvider: SessionClientProviding) async {
        let config = store.loadConfig()
        guard config.enabled, !config.zoneIds.isEmpty else { return }
        if let lastRun, Date.now.timeIntervalSince(lastRun) < Self.minInterval { return }
        await runCycle(clientProvider: clientProvider)
    }

    /// One monitoring cycle: fetch analytics + ssl per zone → engine → notify + persist.
    @discardableResult
    func runCycle(clientProvider: SessionClientProviding) async -> [MonitorAlert] {
        guard !isRunning else { return [] }
        isRunning = true
        defer { isRunning = false; lastRun = .now }

        let config = store.loadConfig()
        guard config.enabled, !config.zoneIds.isEmpty,
              let client = await clientProvider.currentClient() else { return [] }

        // Resolve zone names in one call (RN parity).
        var zoneNames: [String: String] = [:]
        if let (zones, _): ([Zone], ResultInfo?) = try? await client.sendList(CloudflareEndpoint.zones(page: 1)) {
            for zone in zones { zoneNames[zone.id] = zone.name }
        }

        var inputs: [MonitorEngine.ZoneInput] = []
        for zoneId in config.zoneIds {
            let zoneName = zoneNames[zoneId] ?? String(zoneId.prefix(8))
            do {
                let response = try await client.graphql(query: MonitorEngine.hourlyQuery(zoneId: zoneId)) as MonitorEngine.HourlyResponse
                let hourly = MonitorEngine.hourlyPoints(from: response)
                var sslDays: Int?
                if let packResponse: CloudflareResponse<[CertificatePack]> = try? await client.send(
                    CloudflareEndpoint.sslCertificatePack(zoneId: zoneId)
                ) {
                    sslDays = MonitorEngine.sslDaysLeft(certificatePacks: packResponse.result ?? [])
                }
                inputs.append(MonitorEngine.ZoneInput(zoneId: zoneId, zoneName: zoneName, hourly: hourly, sslDaysLeft: sslDays))
            } catch {
                continue // analytics lost or network hiccup — skip quietly (RN parity)
            }
        }

        var state = store.loadState()
        let alerts = MonitorEngine.run(inputs: inputs, config: config, state: &state)
        store.saveState(state)
        store.pushHistory(alerts)
        notify(alerts)
        return alerts
    }

    private func notify(_ alerts: [MonitorAlert]) {
        guard !alerts.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
                center.add(request)
            }
        }
    }

    /// Requests notification permission — only when the user enables monitoring.
    static func requestNotificationPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }
}

/// Provides a CloudflareClient for the active session (BG tasks start cold; resolve lazily).
nonisolated protocol SessionClientProviding: Sendable {
    func currentClient() async -> CloudflareClient?
}

/// Default provider: rebuilds a client from the active Keychain profile.
nonisolated final class CurrentSessionClient: SessionClientProviding {
    static let shared = CurrentSessionClient()

    func currentClient() async -> CloudflareClient? {
        let profiles = await MainActor.run { ProfileStore().profiles }
        guard let activeId = UserDefaults.standard.string(forKey: ProfileStore.activeKey),
              let profile = profiles.first(where: { $0.id == activeId }) ?? profiles.first else {
            return nil
        }
        return CloudflareClient(auth: profile.auth)
    }
}
