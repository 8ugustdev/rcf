import XCTest
@testable import RCF

/// MonitorEngine pure logic: thresholds, cooldown dedup, ssl days, hourly decode.
final class MonitorTests: XCTestCase {
    private func point(_ requests: Int, _ errors: Int = 0, _ threats: Int = 0) -> MonitorEngine.HourlyPoint {
        MonitorEngine.HourlyPoint(requests: requests, errors: errors, threats: threats)
    }

    func testDownAlertOnHigh5xxRate() {
        var config = MonitorConfig.default
        config.enabled = true
        config.zoneIds = ["z1"]
        var state: MonitorState = [:]
        // Last hour: 50 requests, 15 errors = 30% ≥ 20%, requests ≥ 20.
        let input = MonitorEngine.ZoneInput(zoneId: "z1", zoneName: "example.com", hourly: [
            point(100), point(50, 15),
        ], sslDaysLeft: nil)
        let alerts = MonitorEngine.run(inputs: [input], config: config, state: &state)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].kind, .down)
        XCTAssertTrue(alerts[0].title.contains("returning errors"))
    }

    func testDownSuppressedWhenUnderMinRequests() {
        var config = MonitorConfig.default
        config.enabled = true
        config.zoneIds = ["z1"]
        var state: MonitorState = [:]
        // 100% errors but only 10 requests < 20 min.
        let input = MonitorEngine.ZoneInput(zoneId: "z1", zoneName: "example.com", hourly: [
            point(100), point(10, 10),
        ], sslDaysLeft: nil)
        let alerts = MonitorEngine.run(inputs: [input], config: config, state: &state)
        XCTAssertTrue(alerts.isEmpty)
    }

    func testSpikeAlert() {
        var config = MonitorConfig.default
        config.enabled = true
        config.zoneIds = ["z1"]
        var state: MonitorState = [:]
        let input = MonitorEngine.ZoneInput(zoneId: "z1", zoneName: "example.com", hourly: [
            point(100), point(100), point(100), point(400), // avg 100 ≥ 50, last 400 ≥ 3×
        ], sslDaysLeft: nil)
        let alerts = MonitorEngine.run(inputs: [input], config: config, state: &state)
        XCTAssertEqual(alerts.filter { $0.kind == .spike }.count, 1)
    }

    func testThreatsAlert() {
        var config = MonitorConfig.default
        config.enabled = true
        config.zoneIds = ["z1"]
        var state: MonitorState = [:]
        let input = MonitorEngine.ZoneInput(zoneId: "z1", zoneName: "example.com", hourly: [
            point(100, 0, 5), point(100, 0, 150),
        ], sslDaysLeft: nil)
        let alerts = MonitorEngine.run(inputs: [input], config: config, state: &state)
        XCTAssertEqual(alerts.filter { $0.kind == .threats }.count, 1)
    }

    func testSSLExpiryAlert() {
        var config = MonitorConfig.default
        config.enabled = true
        config.zoneIds = ["z1"]
        var state: MonitorState = [:]
        let input = MonitorEngine.ZoneInput(zoneId: "z1", zoneName: "example.com", hourly: [
            point(100), point(100),
        ], sslDaysLeft: 7) // ≤ 14 default
        let alerts = MonitorEngine.run(inputs: [input], config: config, state: &state)
        XCTAssertEqual(alerts.filter { $0.kind == .ssl }.count, 1)
    }

    func testCooldownSuppressesDuplicates() {
        var config = MonitorConfig.default
        config.enabled = true
        config.zoneIds = ["z1"]
        var state: MonitorState = [:]
        let input = MonitorEngine.ZoneInput(zoneId: "z1", zoneName: "example.com", hourly: [
            point(100), point(50, 25),
        ], sslDaysLeft: nil)

        let first = MonitorEngine.run(inputs: [input], config: config, state: &state, now: Date.now)
        XCTAssertEqual(first.count, 1)

        // Second cycle 10 minutes later: cooldown (1h) suppresses.
        let second = MonitorEngine.run(inputs: [input], config: config, state: &state, now: Date.now.addingTimeInterval(600))
        XCTAssertTrue(second.isEmpty)

        // After cooldown elapses: fires again.
        let third = MonitorEngine.run(inputs: [input], config: config, state: &state, now: Date.now.addingTimeInterval(3700))
        XCTAssertEqual(third.count, 1)
    }

    func testDisabledConfigProducesNothing() {
        var config = MonitorConfig.default
        config.enabled = false
        config.zoneIds = ["z1"]
        var state: MonitorState = [:]
        let input = MonitorEngine.ZoneInput(zoneId: "z1", zoneName: "example.com", hourly: [point(100), point(50, 49)], sslDaysLeft: nil)
        XCTAssertTrue(MonitorEngine.run(inputs: [input], config: config, state: &state).isEmpty)
    }

    func testUnselectedZoneSkipped() {
        var config = MonitorConfig.default
        config.enabled = true
        config.zoneIds = ["other"]
        var state: MonitorState = [:]
        let input = MonitorEngine.ZoneInput(zoneId: "z1", zoneName: "example.com", hourly: [point(100), point(50, 49)], sslDaysLeft: nil)
        XCTAssertTrue(MonitorEngine.run(inputs: [input], config: config, state: &state).isEmpty)
    }

    func testHourlyDecodeFromGraphQLFixture() throws {
        let fixture = """
        {"viewer":{"zones":[{"httpRequests1hGroups":[
          {"dimensions":{"datetime":"2026-08-23T09:00:00Z"},"sum":{"requests":100,"threats":3,"responseStatusMap":[{"edgeResponseStatus":200,"requests":95},{"edgeResponseStatus":500,"requests":5}]}},
          {"dimensions":{"datetime":"2026-08-23T10:00:00Z"},"sum":{"requests":200,"threats":0,"responseStatusMap":[{"edgeResponseStatus":200,"requests":150},{"edgeResponseStatus":502,"requests":50}]}}
        ]}]}}
        """
        let response = try JSONDecoder().decode(MonitorEngine.HourlyResponse.self, from: Data(fixture.utf8))
        let points = MonitorEngine.hourlyPoints(from: response)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].requests, 100)
        XCTAssertEqual(points[0].errors, 5)
        XCTAssertEqual(points[1].errors, 50) // 502 counted as 5xx
    }

    func testSSLDaysLeftComputation() {
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let soon = now.addingTimeInterval(7 * 86_400)
        let later = now.addingTimeInterval(90 * 86_400)
        let formatter = ISO8601DateFormatter()
        let packs = [
            CertificatePack(id: "1", status: "active", hosts: nil, certificateAuthority: nil,
                            validity: .init(startsOn: nil, expiresOn: formatter.string(from: later)),
                            validationRecords: nil),
            CertificatePack(id: "2", status: "active", hosts: nil, certificateAuthority: nil,
                            validity: .init(startsOn: nil, expiresOn: formatter.string(from: soon)),
                            validationRecords: nil),
        ]
        XCTAssertEqual(MonitorEngine.sslDaysLeft(certificatePacks: packs, now: now), 7)
        XCTAssertNil(MonitorEngine.sslDaysLeft(certificatePacks: [], now: now))
    }

    func testHistoryCapAndClear() {
        let store = MonitorStore(keychain: KeychainStore(service: "monitor.tests.\(UUID().uuidString)"))
        XCTAssertTrue(store.loadHistory().isEmpty)
        let alert = MonitorAlert(id: "a1", kind: .down, zoneName: "z", title: "t", body: "b", at: .now)
        store.pushHistory([alert])
        XCTAssertEqual(store.loadHistory().count, 1)
        store.clearHistory()
        XCTAssertTrue(store.loadHistory().isEmpty)
    }
}
