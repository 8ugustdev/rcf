import XCTest
@testable import RCF

@MainActor
final class ZoneDetailTests: XCTestCase {
    func testInitialZoneKeepsDetailUsableWhenOptionalEndpointsRejectGlobalKey() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = CloudflareClient(
            auth: .globalKey(email: "user@example.com", key: "test-key"),
            session: URLSession(configuration: config)
        )
        let zoneJSON = """
        {"id":"z1","name":"example.com","status":"active","paused":false,"type":"full",
         "development_mode":0,"name_servers":["ns1.cloudflare.com"],
         "modified_on":null,"created_on":null,"activated_on":null,
         "plan":{"id":"p","name":"Free","price":0,"currency":"USD","frequency":"","is_subscribed":false},
         "account":{"id":"a1","name":"Account"}}
        """
        let zone = try JSONDecoder().decode(Zone.self, from: Data(zoneJSON.utf8))
        let session = Session(client: client, profile: Profile(label: "Global", auth: .globalKey(email: "user@example.com", key: "test-key")))
        let model = ZoneDetailViewModel(zoneId: zone.id, session: session, initialZone: zone)

        MockURLProtocol.reset()
        for _ in 0..<3 {
            MockURLProtocol.enqueue(.init(statusCode: 401, data: Data("{}".utf8)))
        }
        await model.load()

        guard case .loaded = model.state else { return XCTFail("detail should remain loaded") }
        XCTAssertEqual(model.zone?.id, "z1")
        XCTAssertEqual(MockURLProtocol.requests.count, 3)
        XCTAssertFalse(MockURLProtocol.requests.contains { $0.url?.path == "/client/v4/zones/z1" })
    }
}
