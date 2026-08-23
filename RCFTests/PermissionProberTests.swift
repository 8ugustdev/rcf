import XCTest
@testable import RCF

final class PermissionProberTests: XCTestCase {
    private func makeProber() -> PermissionProber {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = CloudflareClient(
            auth: .globalKey(email: "user@example.com", key: "test-key"),
            session: URLSession(configuration: configuration)
        )
        return PermissionProber(client: client)
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    func testAccessProbeIgnoresUnknownDNSRecordType() async {
        // OPENPGPKEY is deliberately outside DNSRecordType. Permission detection
        // should still succeed because the API authorized and returned success.
        let response = """
        {"success":true,"errors":[],"messages":[],"result":[
          {"id":"r1","type":"OPENPGPKEY","name":"user.example.com","content":"data"}
        ]}
        """
        MockURLProtocol.enqueue(.init(data: Data(response.utf8)))
        let allowed = await makeProber().probeAccess(CloudflareRequest(path: "/zones/z1/dns_records"))
        XCTAssertTrue(allowed)
    }

    func testAccessProbeReturnsFalseForUnauthorizedEnvelope() async {
        let response = """
        {"success":false,"errors":[{"code":9109,"message":"Unauthorized"}],"messages":[],"result":null}
        """
        MockURLProtocol.enqueue(.init(data: Data(response.utf8)))
        let allowed = await makeProber().probeAccess(CloudflareRequest(path: "/zones/z1/dns_records"))
        XCTAssertFalse(allowed)
    }
}
